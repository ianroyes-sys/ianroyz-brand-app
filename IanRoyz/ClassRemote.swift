import Foundation
import UIKit

// MARK: - The class wall, over Supabase
//
// Plain PostgREST + Storage over URLSession — no SDK, because the whole surface
// is six tables and one bucket and a package dependency would outweigh it.
//
// Nothing here runs until `ClassConfig` has a URL and an anon key: `ClassRoll`
// picks `LocalClassBackend` when it doesn't, so an unconfigured build behaves
// exactly like a device-only class instead of erroring at people. The schema
// these calls expect is checked in at `supabase/class-roll.sql`.

enum ClassConfig {
    /// Read from Info.plist, which is filled from `Config/Secrets.xcconfig`
    /// (see `Config/Secrets.example.xcconfig`). The key is the *publishable*
    /// one and is meant to ship in the binary: every table is behind RLS keyed
    /// to the anonymous auth user. Never put the secret key here.
    static let supabaseURL: String = {
        let host = (Bundle.main.object(forInfoDictionaryKey: "SupabaseHost") as? String ?? "")
            .trimmingCharacters(in: .whitespaces)
        return host.isEmpty ? "" : "https://\(host)"
    }()
    static let anonKey: String = (Bundle.main.object(forInfoDictionaryKey: "SupabaseAnonKey") as? String ?? "")
        .trimmingCharacters(in: .whitespaces)

    static var isConfigured: Bool { !supabaseURL.isEmpty && !anonKey.isEmpty }
    static var base: URL? { URL(string: supabaseURL) }
    static let bucket = "wall"
}

/// Anonymous Supabase session. Nobody signs up to look at a class wall — the
/// device gets an anonymous user on first use and that identity is the author.
actor ClassSession {
    static let shared = ClassSession()
    private var token: String?
    private var userID: String?

    private var storedToken: String? {
        get { UserDefaults.standard.string(forKey: "classAccessToken") }
        set { UserDefaults.standard.set(newValue, forKey: "classAccessToken") }
    }
    private var storedRefresh: String? {
        get { UserDefaults.standard.string(forKey: "classRefreshToken") }
        set { UserDefaults.standard.set(newValue, forKey: "classRefreshToken") }
    }

    func accessToken() async throws -> String {
        if let token { return token }
        if let cached = storedToken, !cached.isEmpty {
            token = cached
            return cached
        }
        guard let base = ClassConfig.base else { throw ClassError.notConfigured }

        var req = URLRequest(url: base.appendingPathComponent("auth/v1/signup"))
        req.httpMethod = "POST"
        req.setValue(ClassConfig.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = "{}".data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = json["access_token"] as? String else { throw ClassError.badResponse }

        token = access
        storedToken = access
        storedRefresh = json["refresh_token"] as? String
        userID = (json["user"] as? [String: Any])?["id"] as? String
        return access
    }

    /// Called when a request comes back 401 — the anonymous token expired and
    /// the next call should mint a fresh one rather than fail the room.
    func invalidate() {
        token = nil
        storedToken = nil
    }
}

struct RemoteClassBackend: ClassBackend {

    // MARK: Wire shapes

    private struct ClassRow: Codable {
        var id: String
        var code: String
        var name: String
        var started_at: Date
        var graduation: Date
        var prompt: String?
        var member_count: Int?
    }

    private struct DropRow: Codable {
        var id: String
        var class_id: String
        var author_id: String
        var author_handle: String
        var author_name: String
        var author_avatar: String?
        var week: String
        var dropped_at: Date
        var grade_id: String
        var caption: String?
        var path: String
        var keeps: Int?
        var kept_by_me: Bool?
        var notes: [NoteRow]?
    }

    private struct NoteRow: Codable {
        var id: String
        var author_id: String
        var author_handle: String
        var text: String
        var created_at: Date
    }

    // MARK: Requests

    private func request(_ path: String, method: String = "GET",
                         body: Data? = nil, contentType: String = "application/json",
                         prefer: String? = nil, query: String? = nil,
                         headers: [String: String] = [:]) async throws -> Data {
        guard let base = ClassConfig.base else { throw ClassError.notConfigured }
        var url = base.appendingPathComponent(path)
        if let query, var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            comps.query = query
            url = comps.url ?? url
        }

        func send() async throws -> (Data, HTTPURLResponse) {
            var req = URLRequest(url: url)
            req.httpMethod = method
            req.timeoutInterval = 15
            req.setValue(ClassConfig.anonKey, forHTTPHeaderField: "apikey")
            // A session is required to write, but not to look. If the anonymous
            // sign-in can't be minted the request still goes out as `anon`, so
            // the wall stays readable and only the writes fail.
            if let token = try? await ClassSession.shared.accessToken() {
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            req.setValue(contentType, forHTTPHeaderField: "Content-Type")
            if let prefer { req.setValue(prefer, forHTTPHeaderField: "Prefer") }
            for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
            req.httpBody = body
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else { throw ClassError.badResponse }
            return (data, http)
        }

        var (data, http) = try await send()
        if http.statusCode == 401 {
            await ClassSession.shared.invalidate()
            (data, http) = try await send()
        }
        guard (200..<300).contains(http.statusCode) else { throw ClassError.badResponse }
        return data
    }

    private var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let s = try decoder.singleValueContainer().decode(String.self)
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = iso.date(from: s) { return d }
            iso.formatOptions = [.withInternetDateTime]
            if let d = iso.date(from: s) { return d }
            let day = DateFormatter()
            day.dateFormat = "yyyy-MM-dd"
            if let d = day.date(from: s) { return d }
            throw ClassError.badResponse
        }
        return d
    }

    private func info(from row: ClassRow) -> ClassInfo {
        ClassInfo(id: row.id, code: row.code, name: row.name, startedAt: row.started_at,
                  graduation: row.graduation, prompt: row.prompt, memberCount: row.member_count ?? 1)
    }

    // MARK: Joining

    func join(code: String, as me: ClassProfile) async throws -> ClassInfo {
        let data = try await request("rest/v1/classes", query: "code=eq.\(code)&select=*&limit=1")
        guard let row = try decoder.decode([ClassRow].self, from: data).first else { throw ClassError.noSuchClass }
        try await enroll(in: row.id, as: me)
        return info(from: row)
    }

    func create(name: String, code: String, graduation: Date, by me: ClassProfile) async throws -> ClassInfo {
        let iso = ISO8601DateFormatter()
        let payload: [String: Any] = [
            "code": code,
            "name": name.uppercased(),
            "started_at": iso.string(from: Date()),
            "graduation": iso.string(from: graduation),
        ]
        let data = try await request("rest/v1/classes", method: "POST",
                                     body: try JSONSerialization.data(withJSONObject: [payload]),
                                     prefer: "return=representation")
        guard let row = try decoder.decode([ClassRow].self, from: data).first else { throw ClassError.badResponse }
        try await enroll(in: row.id, as: me)
        return info(from: row)
    }

    /// Upsert of the roster row — also how a handle/avatar change propagates.
    private func enroll(in classID: String, as me: ClassProfile) async throws {
        let payload: [String: Any] = [
            "class_id": classID,
            "member_id": me.id,
            "handle": me.handle,
            "name": me.name,
        ]
        _ = try? await request("rest/v1/members", method: "POST",
                               body: try JSONSerialization.data(withJSONObject: [payload]),
                               prefer: "resolution=merge-duplicates")
        await uploadAvatar(for: me, in: classID)
    }

    /// The face, to a fixed path per member. Without this the wall is a grid of
    /// initials: `author_avatar` is a filename that only ever existed on the
    /// author's own phone, so nobody else could resolve it.
    private func uploadAvatar(for me: ClassProfile, in classID: String) async {
        guard me.avatarFile != nil else { return }
        // Same resolver the views use (profile dir → wall cache → bundle), so a
        // face set any of those ways still reaches the wall.
        guard let ui = await ClassRoll.shared.avatarImage(named: me.avatarFile) else { return }

        // Small and square — this is drawn at 20–40pt, never full screen.
        let side: CGFloat = 256
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        let square = renderer.image { _ in
            let scale = max(side / ui.size.width, side / ui.size.height)
            let size = CGSize(width: ui.size.width * scale, height: ui.size.height * scale)
            ui.draw(in: CGRect(x: (side - size.width) / 2, y: (side - size.height) / 2,
                               width: size.width, height: size.height))
        }
        guard let data = square.jpegData(compressionQuality: 0.85) else { return }

        _ = try? await request("storage/v1/object/\(ClassConfig.bucket)/\(Self.avatarPath(classID, me.id))",
                               method: "POST", body: data, contentType: "image/jpeg",
                               prefer: "return=minimal", headers: ["x-upsert": "true"])
    }

    static func avatarPath(_ classID: String, _ memberID: String) -> String {
        "\(classID)/avatars/\(memberID).jpg"
    }

    // MARK: The wall

    func wall(for info: ClassInfo, as me: ClassProfile, cache: URL) async throws -> [Drop] {
        // One RPC, not a table read: `class_wall` folds keep counts, whether
        // this viewer kept each frame, and the notes into each row, so a
        // graduation-length wall is one round trip instead of N+1.
        let body = try JSONSerialization.data(withJSONObject: [
            "p_class": info.id, "p_viewer": me.id, "p_limit": 500,
        ])
        let data = try await request("rest/v1/rpc/class_wall", method: "POST", body: body)
        let rows = try decoder.decode([DropRow].self, from: data)

        var out: [Drop] = []
        for row in rows {
            let file = "\(row.id).jpg"
            let local = cache.appendingPathComponent(file)
            let remote = "\(ClassConfig.supabaseURL)/storage/v1/object/public/\(ClassConfig.bucket)/\(row.path)"

            // Pull each classmate's face down once and hand the view a plain
            // filename, so `AvatarBubble` stays a synchronous cache lookup.
            var avatarFile: String?
            if let stored = row.author_avatar, !stored.isEmpty {
                let cached = "avatar-\(row.author_id).jpg"
                if FileManager.default.fileExists(atPath: cache.appendingPathComponent(cached).path) {
                    avatarFile = cached
                } else {
                    let url = stored.hasPrefix("http") ? stored
                        : "\(ClassConfig.supabaseURL)/storage/v1/object/public/\(ClassConfig.bucket)/\(stored)"
                    if let u = URL(string: url), let (d, r) = try? await URLSession.shared.data(from: u),
                       (r as? HTTPURLResponse)?.statusCode == 200, !d.isEmpty {
                        try? d.write(to: cache.appendingPathComponent(cached), options: .atomic)
                        avatarFile = cached
                    }
                }
            }

            // Images are cached on first sight; the wall is browsed far more
            // often than it changes, and a graduation-length archive should not
            // re-download every launch.
            if !FileManager.default.fileExists(atPath: local.path),
               let url = URL(string: remote),
               let (data, _) = try? await URLSession.shared.data(from: url) {
                try? data.write(to: local, options: .atomic)
            }

            let day = DateFormatter()
            day.dateFormat = "yyyy-MM-dd"
            out.append(Drop(
                id: row.id, authorID: row.author_id, authorHandle: row.author_handle,
                authorName: row.author_name, authorAvatar: avatarFile,
                week: day.date(from: row.week) ?? row.dropped_at,
                droppedAt: row.dropped_at, gradeID: row.grade_id, caption: row.caption,
                file: file, remoteURL: remote, keeps: row.keeps ?? 0,
                keptByMe: row.kept_by_me ?? false,
                notes: (row.notes ?? []).map {
                    Note(id: $0.id, authorID: $0.author_id, authorHandle: $0.author_handle,
                         text: $0.text, at: $0.created_at)
                }))
        }
        return out
    }

    func publish(_ drop: Drop, data: Data, in info: ClassInfo, as me: ClassProfile) async throws -> Drop {
        let path = "\(info.id)/\(drop.id).jpg"
        _ = try await request("storage/v1/object/\(ClassConfig.bucket)/\(path)",
                              method: "POST", body: data, contentType: "image/jpeg")

        let day = DateFormatter()
        day.dateFormat = "yyyy-MM-dd"
        let iso = ISO8601DateFormatter()
        var payload: [String: Any] = [
            "id": drop.id,
            "class_id": info.id,
            "author_id": me.id,
            "author_handle": me.handle,
            "author_name": me.name,
            "week": day.string(from: drop.week),
            "dropped_at": iso.string(from: drop.droppedAt),
            "grade_id": drop.gradeID,
            "path": path,
        ]
        if let caption = drop.caption { payload["caption"] = caption }
        // The path everybody can resolve, not this phone's local filename.
        if me.avatarFile != nil { payload["author_avatar"] = Self.avatarPath(info.id, me.id) }

        _ = try await request("rest/v1/drops", method: "POST",
                              body: try JSONSerialization.data(withJSONObject: [payload]))
        var out = drop
        out.remoteURL = "\(ClassConfig.supabaseURL)/storage/v1/object/public/\(ClassConfig.bucket)/\(path)"
        return out
    }

    func keep(_ drop: Drop, kept: Bool, in info: ClassInfo, as me: ClassProfile) async throws {
        if kept {
            let payload: [String: Any] = ["drop_id": drop.id, "member_id": me.id]
            _ = try await request("rest/v1/keeps", method: "POST",
                                  body: try JSONSerialization.data(withJSONObject: [payload]),
                                  prefer: "resolution=ignore-duplicates")
        } else {
            _ = try await request("rest/v1/keeps", method: "DELETE",
                                  query: "drop_id=eq.\(drop.id)&member_id=eq.\(me.id)")
        }
    }

    func note(_ note: Note, on drop: Drop, in info: ClassInfo, as me: ClassProfile) async throws {
        let payload: [String: Any] = [
            "id": note.id, "drop_id": drop.id, "author_id": me.id,
            "author_handle": me.handle, "text": note.text,
        ]
        _ = try await request("rest/v1/notes", method: "POST",
                              body: try JSONSerialization.data(withJSONObject: [payload]))
    }

    func delete(_ drop: Drop, in info: ClassInfo, as me: ClassProfile) async throws {
        _ = try await request("rest/v1/drops", method: "DELETE",
                              query: "id=eq.\(drop.id)&author_id=eq.\(me.id)")
    }

    func report(_ drop: Drop, reason: String, in info: ClassInfo, as me: ClassProfile) async throws {
        let payload: [String: Any] = [
            "drop_id": drop.id, "class_id": info.id,
            "reporter_id": me.id, "reason": reason,
        ]
        _ = try await request("rest/v1/reports", method: "POST",
                              body: try JSONSerialization.data(withJSONObject: [payload]))
    }
}
