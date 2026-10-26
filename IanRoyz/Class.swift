import Foundation
import SwiftUI

// MARK: - THE CLASS ROLL
//
// THE ROLL is one person's week, sealed. THE CLASS ROLL is what happens the
// second it opens: at 6:40 on Saturday every roll in the class develops at the
// same moment, and the frames land together in one wall.
//
// Two rules hold the whole thing up:
//
//  1. Nothing appears before Saturday. Not yours, not anybody's. The wall for a
//     week that hasn't developed does not exist yet — `Volume.isOpen` is the
//     only gate, and there is no path around it.
//  2. Everybody drops at once. There is no "posting" all week, so there is no
//     feed to check, no first-mover advantage, no algorithm. You get one moment
//     a week and everybody is in it together.
//
// The wall stacks by week and runs to graduation: 42 Saturdays, one volume each,
// and at the end the whole thing is the yearbook.

// MARK: Models

/// Who you are inside the class. Deliberately thin — a handle, a name and a face.
struct ClassProfile: Codable, Identifiable, Hashable {
    var id: String
    var handle: String          // "notsoian", stored without the @
    var name: String
    var avatarFile: String?     // filename in the profile directory
    var joinedAt: Date

    var display: String { "@\(handle)" }
    var initials: String { ClassRoll.initials(name: name, handle: handle) }
}

/// The class itself. A code, a name, and the date the whole thing is running at.
struct ClassInfo: Codable, Hashable {
    var id: String
    var code: String            // join code, uppercased — "SPRING27"
    var name: String            // "THE CLASS OF 2027"
    var startedAt: Date
    var graduation: Date
    var prompt: String?         // this week's theme, if the class is running one
    var memberCount: Int

    /// Saturdays from the first one to graduation.
    var totalWeeks: Int {
        let cal = Calendar.current
        let a = ClassRoll.weekStart(for: startedAt), b = ClassRoll.weekStart(for: graduation)
        let days = cal.dateComponents([.day], from: a, to: b).day ?? 0
        return max(1, days / 7 + 1)
    }

    /// Saturdays already developed, capped at the total.
    var weeksIn: Int {
        let cal = Calendar.current
        let a = ClassRoll.weekStart(for: startedAt)
        let days = cal.dateComponents([.day], from: a, to: ClassRoll.weekStart(for: Date())).day ?? 0
        return min(totalWeeks, max(0, days / 7 + 1))
    }

    var weeksLeft: Int { max(0, totalWeeks - weeksIn) }
    var progress: Double { totalWeeks == 0 ? 0 : Double(weeksIn) / Double(totalWeeks) }
    var hasGraduated: Bool { Date() >= graduation }
}

/// One frame on the wall. `week` is the Saturday it developed on — never the day
/// it was shot, because the whole class shares the develop moment, not the shoot.
struct Drop: Identifiable, Codable, Hashable {
    var id: String
    var authorID: String
    var authorHandle: String
    var authorName: String
    var authorAvatar: String?
    var week: Date              // normalised develop Saturday
    var droppedAt: Date
    var gradeID: String
    var caption: String?
    var file: String            // filename in the wall cache, or a remote path
    var remoteURL: String?
    var keeps: Int
    var keptByMe: Bool
    var notes: [Note]

    var grade: Grade { Grade.named(gradeID) }
}

/// A line under a frame. Capped short on purpose — this is a darkroom wall, not
/// a comment section.
struct Note: Identifiable, Codable, Hashable {
    var id: String
    var authorID: String
    var authorHandle: String
    var text: String
    var at: Date
    static let limit = 140
}

/// One Saturday's wall.
struct Volume: Identifiable, Hashable {
    var id: String { ClassRoll.key(for: week) }
    let week: Date
    let number: Int             // 1-based week index inside the class
    let drops: [Drop]

    /// A volume opens the instant its Saturday 6:40 passes. Before that it does
    /// not render at all — see the note at the top of this file.
    var isOpen: Bool { Date() >= week }

    var contributors: Int { Set(drops.map(\.authorID)).count }
}

// MARK: - The store

@MainActor
final class ClassRoll: ObservableObject {
    static let shared = ClassRoll()
    static let communityCode = "SATURDAY"
    static let communityName = "THE SATURDAY WALL"

    @Published private(set) var profile: ClassProfile?
    @Published private(set) var info: ClassInfo?
    @Published private(set) var drops: [Drop] = []
    @Published private(set) var syncing = false
    @Published private(set) var lastError: String?
    /// Handles this device has blocked. Their frames never reach the wall.
    @Published private(set) var blocked: Set<String> = []
    /// Set once the rules have been agreed to; a first drop is gated on it.
    @AppStorage("classRulesAccepted") var rulesAccepted = false

    private let backend: ClassBackend
    private let fm = FileManager.default
    private let defaults = UserDefaults.standard

    var isMember: Bool { profile != nil && info != nil }
    var isInCommunity: Bool { info?.code == Self.communityCode }

    private init() {
        backend = ClassConfig.isConfigured ? RemoteClassBackend() : LocalClassBackend()
        loadLocalState()
        seedIfRequested()
    }

    // MARK: Directories

    /// Where wall images live. Cached, not Documents — the wall can always be
    /// re-fetched, so it must never eat backup space it doesn't own.
    var wallDirectory: URL {
        let base = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("classroll", isDirectory: true)
        if !fm.fileExists(atPath: base.path) {
            try? fm.createDirectory(at: base, withIntermediateDirectories: true)
        }
        return base
    }

    var profileDirectory: URL {
        let base = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("profile", isDirectory: true)
        if !fm.fileExists(atPath: base.path) {
            try? fm.createDirectory(at: base, withIntermediateDirectories: true)
        }
        return base
    }

    func image(for drop: Drop) -> UIImage? {
        let local = wallDirectory.appendingPathComponent(drop.file)
        if let ui = UIImage(contentsOfFile: local.path) { return ui }
        // Bundled seed frames (debug class only).
        return bundleImage(drop.file.replacingOccurrences(of: ".jpg", with: ""))
    }

    func avatar(for profile: ClassProfile) -> UIImage? {
        guard let file = profile.avatarFile else { return nil }
        if let ui = UIImage(contentsOfFile: profileDirectory.appendingPathComponent(file).path) { return ui }
        if let ui = UIImage(contentsOfFile: wallDirectory.appendingPathComponent(file).path) { return ui }
        return bundleImage(file.replacingOccurrences(of: ".jpg", with: ""))
    }

    func avatarImage(named file: String?) -> UIImage? {
        guard let file else { return nil }
        if let ui = UIImage(contentsOfFile: profileDirectory.appendingPathComponent(file).path) { return ui }
        if let ui = UIImage(contentsOfFile: wallDirectory.appendingPathComponent(file).path) { return ui }
        return bundleImage(file.replacingOccurrences(of: ".jpg", with: ""))
    }

    // MARK: Volumes — the wall, stacked by Saturday

    /// Newest Saturday first. Weeks that haven't developed are not here at all.
    var volumes: [Volume] {
        guard let info else { return [] }
        let visible = drops.filter { !blocked.contains($0.authorID) }
        let grouped = Dictionary(grouping: visible) { Self.weekStart(for: $0.week) }
        return grouped.keys.sorted(by: >)
            .map { week in
                Volume(week: week,
                       number: Self.weekNumber(of: week, in: info),
                       drops: (grouped[week] ?? []).sorted { $0.droppedAt > $1.droppedAt })
            }
            .filter(\.isOpen)   // rule 1: a week that hasn't developed doesn't exist yet
    }

    /// The most recent volume that has actually opened.
    var latestVolume: Volume? { volumes.first }

    func isMine(_ drop: Drop) -> Bool { drop.authorID == profile?.id }

    /// Everyone who has ever dropped, most frames first.
    var classmates: [(handle: String, name: String, avatar: String?, count: Int, id: String)] {
        let visible = drops.filter { !blocked.contains($0.authorID) }
        let grouped = Dictionary(grouping: visible, by: \.authorID)
        return grouped.map { id, ds in
            (handle: ds[0].authorHandle, name: ds[0].authorName,
             avatar: ds[0].authorAvatar, count: ds.count, id: id)
        }
        .sorted { $0.count > $1.count }
    }

    /// How many Saturdays in a row you've dropped into. The one number that
    /// actually pulls people back — miss a Saturday and it resets.
    var streak: Int {
        guard let me = profile?.id else { return 0 }
        let mine = Set(drops.filter { $0.authorID == me }.map { Self.key(for: $0.week) })
        guard !mine.isEmpty else { return 0 }
        var n = 0
        var cursor = Self.weekStart(for: Date())
        // The current Saturday only counts once it has actually developed.
        if Date() < cursor { cursor = cursor.addingTimeInterval(-7 * 86_400) }
        while mine.contains(Self.key(for: cursor)) {
            n += 1
            cursor = cursor.addingTimeInterval(-7 * 86_400)
        }
        return n
    }

    var myDropCount: Int { drops.filter { $0.authorID == profile?.id }.count }

    /// A small editorial shelf, not a popularity feed: the three most-kept
    /// frames currently visible on the open wall.
    var festivalPicks: [Drop] {
        Array(volumes.flatMap(\.drops).sorted {
            $0.keeps == $1.keeps ? $0.droppedAt > $1.droppedAt : $0.keeps > $1.keeps
        }.prefix(3))
    }

    // MARK: Joining

    func createProfile(handle: String, name: String, avatar: UIImage?) {
        let id = profile?.id ?? UUID().uuidString
        var file: String?
        if let avatar, let data = avatar.jpegData(compressionQuality: 0.85) {
            let f = "avatar-\(id).jpg"
            try? data.write(to: profileDirectory.appendingPathComponent(f), options: .atomic)
            file = f
        } else {
            file = profile?.avatarFile
        }
        let clean = handle.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "@", with: "")
            .lowercased()
        profile = ClassProfile(id: id, handle: clean, name: name.trimmingCharacters(in: .whitespaces),
                               avatarFile: file, joinedAt: profile?.joinedAt ?? Date())
        saveLocalState()
    }

    func join(code: String) async {
        guard let profile else { return }
        syncing = true
        defer { syncing = false }
        let clean = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        do {
            let joined = try await backend.join(code: clean, as: profile)
            info = joined
            saveLocalState()
            await refresh()
        } catch {
            lastError = "That code didn't open anything."
        }
    }

    func create(name: String, code: String, graduation: Date) async {
        guard let profile else { return }
        syncing = true
        defer { syncing = false }
        let clean = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        do {
            let made = try await backend.create(name: name, code: clean, graduation: graduation, by: profile)
            info = made
            saveLocalState()
            await refresh()
        } catch {
            lastError = "Couldn't start that class."
        }
    }

    /// Enter the one open room. The first person to arrive creates it; a race
    /// on first launch falls through to join, so no privileged seed account or
    /// invite code is ever required.
    func enterCommunity() async {
        guard let profile else { return }
        if isInCommunity { await refresh(); return }

        syncing = true
        defer { syncing = false }
        lastError = nil

        do {
            info = try await backend.join(code: Self.communityCode, as: profile)
        } catch {
            let ends = Calendar.current.date(byAdding: .year, value: 20, to: Date()) ?? Date()
            do {
                info = try await backend.create(name: Self.communityName,
                                                 code: Self.communityCode,
                                                 graduation: ends,
                                                 by: profile)
            } catch {
                do {
                    info = try await backend.join(code: Self.communityCode, as: profile)
                } catch {
                    lastError = "The wall is taking a minute. Try again."
                    return
                }
            }
        }
        saveLocalState()
        await refresh()
    }

    func leave() {
        info = nil
        drops = []
        saveLocalState()
    }

    // MARK: The wall

    func refresh() async {
        guard let info, let profile else { return }
        syncing = true
        defer { syncing = false }
        do {
            let fetched = try await backend.wall(for: info, as: profile, cache: wallDirectory)
            // A fetch never removes frames this device dropped but hasn't synced.
            let remoteIDs = Set(fetched.map(\.id))
            let pendingMine = drops.filter { $0.authorID == profile.id && !remoteIDs.contains($0.id) }
            drops = (fetched + pendingMine).sorted { $0.droppedAt > $1.droppedAt }
            saveLocalState()
        } catch {
            lastError = nil   // offline is a non-event; the cached wall stays up
        }
    }

    /// Put developed frames on the class wall. Undeveloped frames can't reach
    /// this — `RollStore.image(for:)` refuses to hand them over in the first place.
    func drop(_ shots: [Shot], captions: [UUID: String], from roll: RollStore) async {
        guard let profile, let info else { return }
        syncing = true
        defer { syncing = false }

        for shot in shots {
            guard shot.developed, let ui = roll.image(for: shot),
                  let data = ui.jpegData(compressionQuality: 0.88) else { continue }

            let id = UUID().uuidString
            let file = "\(id).jpg"
            try? data.write(to: wallDirectory.appendingPathComponent(file), options: .atomic)

            var drop = Drop(id: id, authorID: profile.id, authorHandle: profile.handle,
                            authorName: profile.name, authorAvatar: profile.avatarFile,
                            week: Self.weekStart(for: shot.capturedAt),
                            droppedAt: Date(), gradeID: shot.gradeID,
                            caption: captions[shot.id]?.isEmpty == false ? captions[shot.id] : nil,
                            file: file, remoteURL: nil, keeps: 0, keptByMe: false, notes: [])

            drops.insert(drop, at: 0)
            roll.markDropped(shot)

            if let uploaded = try? await backend.publish(drop, data: data, in: info, as: profile) {
                drop = uploaded
                if let i = drops.firstIndex(where: { $0.id == id }) { drops[i] = uploaded }
            }
        }
        saveLocalState()
    }

    func keep(_ drop: Drop) {
        guard let i = drops.firstIndex(where: { $0.id == drop.id }), let info, let profile else { return }
        drops[i].keptByMe.toggle()
        drops[i].keeps += drops[i].keptByMe ? 1 : -1
        let now = drops[i]
        saveLocalState()
        Task { try? await backend.keep(now, kept: now.keptByMe, in: info, as: profile) }
    }

    func addNote(_ text: String, to drop: Drop) {
        guard let profile, let info,
              let i = drops.firstIndex(where: { $0.id == drop.id }) else { return }
        let clean = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Note.limit))
        guard !clean.isEmpty else { return }
        let note = Note(id: UUID().uuidString, authorID: profile.id,
                        authorHandle: profile.handle, text: clean, at: Date())
        drops[i].notes.append(note)
        saveLocalState()
        Task { try? await backend.note(note, on: drop, in: info, as: profile) }
    }

    func deleteMine(_ drop: Drop) {
        guard drop.authorID == profile?.id else { return }
        try? fm.removeItem(at: wallDirectory.appendingPathComponent(drop.file))
        drops.removeAll { $0.id == drop.id }
        saveLocalState()
        if let info, let profile {
            Task { try? await backend.delete(drop, in: info, as: profile) }
        }
    }

    // MARK: Moderation
    //
    // Shared photo walls need a way out of a bad frame on the same screen the
    // frame is on. Blocking is local and immediate — the wall recomputes without
    // that person before the report has gone anywhere.

    func block(_ drop: Drop) {
        blocked.insert(drop.authorID)
        saveLocalState()
    }

    func unblockAll() {
        blocked.removeAll()
        saveLocalState()
    }

    func report(_ drop: Drop, reason: String) {
        guard let info, let profile else { return }
        Task { try? await backend.report(drop, reason: reason, in: info, as: profile) }
    }

    // MARK: Persistence

    private struct Snapshot: Codable {
        var profile: ClassProfile?
        var info: ClassInfo?
        var drops: [Drop]
        var blocked: [String]
    }

    private var snapshotURL: URL {
        fm.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("classroll.json")
    }

    private func loadLocalState() {
        guard let data = try? Data(contentsOf: snapshotURL),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        profile = snap.profile
        info = snap.info
        drops = snap.drops
        blocked = Set(snap.blocked)
    }

    private func saveLocalState() {
        let snap = Snapshot(profile: profile, info: info, drops: drops, blocked: Array(blocked))
        guard let data = try? JSONEncoder().encode(snap) else { return }
        try? data.write(to: snapshotURL, options: .atomic)
    }

    // MARK: The week

    /// The develop Saturday a moment belongs to — 6:40pm, same as `RollStore`.
    /// Every frame in the class normalises to this, which is what makes the wall
    /// arrive as one drop instead of a trickle.
    // nonisolated: the value types above (ClassInfo, Volume) are not main-actor
    // bound and compute their week maths inline.
    nonisolated static func weekStart(for date: Date) -> Date {
        RollStore.developDate(for: date)
    }

    nonisolated static func key(for date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    nonisolated static func weekNumber(of week: Date, in info: ClassInfo) -> Int {
        let days = Calendar.current.dateComponents([.day], from: weekStart(for: info.startedAt), to: week).day ?? 0
        return max(1, days / 7 + 1)
    }

    /// Initials for an avatar with no photo. The name first — the first two
    /// letters of a handle reads as noise ("notsoian" → "NO").
    nonisolated static func initials(name: String?, handle: String) -> String {
        let parts = (name ?? "").split(separator: " ").prefix(2)
        let fromName = parts.compactMap(\.first).map(String.init).joined()
        if !fromName.isEmpty { return fromName.uppercased() }
        return String(handle.prefix(1)).uppercased()
    }

    nonisolated static func label(for week: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: week).uppercased()
    }

    // MARK: Debug seed
    //
    // Same convention as -ROOM / -SEEDROLL: there is no second phone in the
    // simulator, so `-SEEDCLASS n` fabricates a class with n Saturdays of frames
    // from bundled images. Debug arg only; a shipped launch never carries it.

    private func seedIfRequested() {
        let args = ProcessInfo.processInfo.arguments

        // `-JOINCLASS <code>` runs the real join against the configured backend
        // at launch. Joining otherwise means typing a code, and there is no
        // keyboard in a `simctl launch`. Debug arg only.
        if let j = args.firstIndex(of: "-JOINCLASS"), j + 1 < args.count {
            let code = args[j + 1]
            profile = ClassProfile(id: "debug-device", handle: "notsoian",
                                   name: "Ian Royes", avatarFile: "roll_pfp.jpg", joinedAt: Date())
            rulesAccepted = true
            Task { await join(code: code) }
            return
        }

        guard let i = args.firstIndex(of: "-SEEDCLASS"), i + 1 < args.count,
              let weeks = Int(args[i + 1]), weeks > 0 else { return }

        let me = ClassProfile(id: "me-debug", handle: "notsoian", name: "Ian Royes",
                              avatarFile: "roll_pfp.jpg", joinedAt: Date())
        profile = me
        rulesAccepted = true

        let cal = Calendar.current
        let start = cal.date(byAdding: .weekOfYear, value: -(weeks - 1), to: Self.weekStart(for: Date()))!
        info = ClassInfo(id: "debug", code: "SPRING27", name: "THE CLASS OF 2027",
                         startedAt: start,
                         graduation: cal.date(byAdding: .weekOfYear, value: 35, to: Date())!,
                         prompt: "GOLDEN HOUR", memberCount: 24)

        let cast: [(String, String, String)] = [
            ("notsoian", "Ian Royes", "roll_pfp"),
            ("jaythree", "Jay Dormus", "shoot_dormus_DSC03972"),
            ("monele", "Monele", "shoot_monele_DSC02553"),
            ("softgirl", "Aaliyah", "shoot_soft_DSC04978"),
            ("bigmike", "Mike", "shoot_mediaday_DSC04882"),
            ("carwash", "Trey", "shoot_carwash_DSC02485"),
        ]
        let frames = ["shoot_soft_DSC04980", "shoot_joshcar_DSC07933", "shoot_bday_DSC02870",
                      "shoot_airport_DSC00062", "shoot_constr_DSC02110", "shoot_monele_DSC02564",
                      "shoot_mediaday_DSC04895", "shoot_carwash_DSC02528", "shoot_dormus_DSC03975",
                      "shoot_soft_DSC04984", "shoot_joshcar_DSC07949", "shoot_airport_DSC00082"]
        let captions = ["nowhere to be", nil, "she said run it back", nil, "6:40 exactly",
                        nil, "last one before break", "golden hour did that", nil]

        var made: [Drop] = []
        for w in 0..<weeks {
            let week = cal.date(byAdding: .weekOfYear, value: w, to: start)!
            guard Date() >= week else { continue }
            let count = 4 + (w % 4)
            for k in 0..<count {
                let who = cast[(w * 3 + k) % cast.count]
                let frame = frames[(w * 5 + k) % frames.count]
                made.append(Drop(
                    id: "seed-\(w)-\(k)", authorID: "u-\(who.0)", authorHandle: who.0,
                    authorName: who.1, authorAvatar: "\(who.2).jpg", week: week,
                    droppedAt: week.addingTimeInterval(Double(k) * 420),
                    gradeID: Grade.all[(w + k) % Grade.all.count].id,
                    caption: captions[(w * 2 + k) % captions.count],
                    file: "\(frame).jpg", remoteURL: nil,
                    keeps: (w * 7 + k * 3) % 14, keptByMe: k == 1, notes: k == 0 ? [
                        Note(id: "n-\(w)", authorID: "u-monele", authorHandle: "monele",
                             text: "this one. every week you do this.", at: week.addingTimeInterval(900))
                    ] : []))
            }
        }
        drops = made.sorted { $0.droppedAt > $1.droppedAt }
        saveLocalState()
    }
}

// MARK: - Backend seam
//
// The room talks to this and nothing else. `LocalClassBackend` keeps everything
// on the device (so the room is fully usable before there is a server); the
// remote one in `ClassRemote.swift` is the same shape over Supabase.

protocol ClassBackend {
    func join(code: String, as me: ClassProfile) async throws -> ClassInfo
    func create(name: String, code: String, graduation: Date, by me: ClassProfile) async throws -> ClassInfo
    func wall(for info: ClassInfo, as me: ClassProfile, cache: URL) async throws -> [Drop]
    func publish(_ drop: Drop, data: Data, in info: ClassInfo, as me: ClassProfile) async throws -> Drop
    func keep(_ drop: Drop, kept: Bool, in info: ClassInfo, as me: ClassProfile) async throws
    func note(_ note: Note, on drop: Drop, in info: ClassInfo, as me: ClassProfile) async throws
    func delete(_ drop: Drop, in info: ClassInfo, as me: ClassProfile) async throws
    func report(_ drop: Drop, reason: String, in info: ClassInfo, as me: ClassProfile) async throws
}

enum ClassError: Error { case noSuchClass, notConfigured, badResponse }

/// Device-only. Your own class, your own wall — real and persistent, just not
/// shared until the remote backend is switched on.
struct LocalClassBackend: ClassBackend {
    func join(code: String, as me: ClassProfile) async throws -> ClassInfo {
        // Without a server there is nothing to look the code up in, so a join
        // opens a local class under that code rather than failing at people.
        ClassInfo(id: code.lowercased(), code: code,
                  name: "CLASS OF \(Calendar.current.component(.year, from: Date()) + 1)",
                  startedAt: Date(), graduation: defaultGraduation(), prompt: nil, memberCount: 1)
    }

    func create(name: String, code: String, graduation: Date, by me: ClassProfile) async throws -> ClassInfo {
        ClassInfo(id: code.lowercased(), code: code, name: name.uppercased(),
                  startedAt: Date(), graduation: graduation, prompt: nil, memberCount: 1)
    }

    /// Throws rather than returning an empty wall: `refresh()` treats a failure
    /// as "nothing new" and keeps what's on the device, and an empty array here
    /// would instead read as "the class has nothing" and blank it.
    func wall(for info: ClassInfo, as me: ClassProfile, cache: URL) async throws -> [Drop] {
        throw ClassError.notConfigured
    }
    func publish(_ drop: Drop, data: Data, in info: ClassInfo, as me: ClassProfile) async throws -> Drop { drop }
    func keep(_ drop: Drop, kept: Bool, in info: ClassInfo, as me: ClassProfile) async throws {}
    func note(_ note: Note, on drop: Drop, in info: ClassInfo, as me: ClassProfile) async throws {}
    func delete(_ drop: Drop, in info: ClassInfo, as me: ClassProfile) async throws {}
    func report(_ drop: Drop, reason: String, in info: ClassInfo, as me: ClassProfile) async throws {}

    private func defaultGraduation() -> Date {
        Calendar.current.date(byAdding: .weekOfYear, value: 42, to: Date()) ?? Date()
    }
}
