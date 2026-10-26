import Foundation
import SwiftUI

// MARK: - Live copy
//
// The rooms that go stale are the *written* ones — the rotation, what's playing,
// the series phase. Those were baked into `Media.swift`, so "JULY ROTATION" was
// still on screen in August and the only way to change a line of copy was a full
// App Store review.
//
// This overlays a small remote JSON on top of the bundled defaults. Films and
// episodes deliberately stay in `Archive`: they point at bundled video files, so
// there is nothing to gain by making them remote and a broken room to lose.
//
// Order of truth: bundled defaults → last good cached fetch → this launch's fetch.
// Every field is optional; anything the JSON omits keeps its bundled value, so a
// half-written file can never blank the app.

@MainActor
final class Live: ObservableObject {
    static let shared = Live()

    /// Where the copy lives. A 404 or no network is a non-event — the app just
    /// keeps showing what shipped with it.
    static let feedURL = URL(string: "https://ianroyes.vercel.app/app/ianroyz-live.json")!

    @Published private(set) var copy = LiveCopy.bundled

    private var cacheURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("live.json")
    }

    private init() {
        if let data = try? Data(contentsOf: cacheURL),
           let cached = try? JSONDecoder().decode(LiveCopy.self, from: data) {
            copy = cached.merged(onto: .bundled)
        }
    }

    func refresh() async {
        var request = URLRequest(url: Self.feedURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 8

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let fetched = try? JSONDecoder().decode(LiveCopy.self, from: data) else { return }

        copy = fetched.merged(onto: .bundled)
        try? data.write(to: cacheURL, options: .atomic)
    }
}

/// Every field optional — an omitted key means "keep what shipped".
///
/// The music fields went out with the SOUNDS room (2026-08-07). Anything the
/// feed still sends for them is simply ignored: unknown keys have never been an
/// error here, so an older JSON on the server can't break a build that dropped
/// the room.
struct LiveCopy: Codable {
    var marquee: [String]?
    /// The line the class wall runs under its header — the one bit of the roll
    /// worth being able to change without a review.
    var classPrompt: String?
    /// Optional credit for a guest-directed Saturday. It is intentionally just
    /// copy — a half-written feed must never break the wall.
    var guestName: String?
    var guestHandle: String?

    static let bundled = LiveCopy(
        marquee: ["SATURDAYS", "THE ROLL", "ROYZ FILMZ", "LOST FILES VOL.1", "NOTSOIAN", "UNAPOLOGETIC CREATIVE"],
        classPrompt: "SHOOT THE LIGHT THAT FINDS YOU",
        guestName: "IAN ROYZ",
        guestHandle: "notsoian"
    )

    /// Field-by-field fallback. A nil here never blanks a room.
    func merged(onto base: LiveCopy) -> LiveCopy {
        LiveCopy(
            marquee: (marquee?.isEmpty == false ? marquee : nil) ?? base.marquee,
            classPrompt: classPrompt ?? base.classPrompt,
            guestName: guestName ?? base.guestName,
            guestHandle: guestHandle ?? base.guestHandle
        )
    }
}
