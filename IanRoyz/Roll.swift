import Foundation
import SwiftUI
@preconcurrency import UserNotifications

// MARK: - THE ROLL
//
// A disposable camera that develops on Saturday. You shoot all week and cannot
// see a single frame; Saturday at 6:40pm — the hour the whole archive is about —
// the roll develops and the week comes back graded, all at once.
//
// The delay IS the product. Nothing here should ever quietly reveal a shot early:
// `Shot.image` refuses to load an undeveloped frame, and that is the one invariant
// this file exists to protect.

struct Shot: Identifiable, Codable, Hashable {
    let id: UUID
    let capturedAt: Date
    let gradeID: String
    /// Filename inside `RollStore.directory`. Raw until developed, graded after.
    let file: String
    var developed: Bool
    /// Optional, not a defaulted Bool: a synthesized decoder throws on a missing
    /// key, and rolls written before the class wall existed don't have one.
    var dropped: Bool?

    var grade: Grade { Grade.named(gradeID) }
    var isDropped: Bool { dropped == true }
}

@MainActor
final class RollStore: ObservableObject {
    static let shared = RollStore()

    @Published private(set) var shots: [Shot] = []
    @Published private(set) var developing = false
    /// Set after a develop so the room can run the reveal once.
    @Published var justDeveloped: [Shot] = []

    private let fm = FileManager.default

    private var directory: URL {
        let base = fm.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("roll", isDirectory: true)
        if !fm.fileExists(atPath: base.path) {
            try? fm.createDirectory(at: base, withIntermediateDirectories: true)
        }
        return base
    }
    private var indexURL: URL { directory.appendingPathComponent("roll.json") }

    private init() {
        load()
        seedIfRequested()
    }

    /// Debug only, same convention as `-ROOM`: `-SEEDROLL 4` puts four bundled
    /// stills into the roll, `-DEVELOPNOW` ignores the Saturday gate. There is no
    /// camera in the simulator, so without this the develop path can't be seen.
    private func seedIfRequested() {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-SEEDROLL"), i + 1 < args.count,
              let n = Int(args[i + 1]), n > 0 else { return }

        // Start from a clean roll so repeated launches don't pile up.
        for shot in shots { try? fm.removeItem(at: url(for: shot)) }
        shots = []

        // Bundled photo work stands in for camera frames; STILLS used to supply
        // these and no longer exists.
        let sources = Archive.shoots.flatMap(\.images).prefix(n)
        for (k, name) in sources.enumerated() {
            guard let ui = bundleImage(name) else { continue }
            add(ui, grade: Grade.all[k % Grade.all.count])
        }
    }

    /// True when `-DEVELOPNOW` was passed. Debug builds only in practice —
    /// a shipped launch never carries it.
    var forceDevelop: Bool { ProcessInfo.processInfo.arguments.contains("-DEVELOPNOW") }

    // MARK: Reading

    var undeveloped: [Shot] { shots.filter { !$0.developed }.sorted { $0.capturedAt < $1.capturedAt } }
    var developed: [Shot] { shots.filter(\.developed).sorted { $0.capturedAt > $1.capturedAt } }

    /// Only frames whose own Saturday has arrived may develop. A shot taken
    /// after 6:40 on a Saturday belongs to the following week's roll.
    var readyToDevelop: [Shot] {
        let now = Date()
        return undeveloped.filter { forceDevelop || now >= Self.developDate(for: $0.capturedAt) }
    }

    /// True once at least one sealed frame has reached its develop moment.
    var isReady: Bool {
        !readyToDevelop.isEmpty
    }

    func url(for shot: Shot) -> URL { directory.appendingPathComponent(shot.file) }

    /// The only way to get pixels out. An undeveloped frame is never returned —
    /// this is the guarantee the whole feature rests on.
    func image(for shot: Shot) -> UIImage? {
        guard shot.developed else { return nil }
        return UIImage(contentsOfFile: url(for: shot).path)
    }

    // MARK: Shooting

    /// Stores the frame ungraded. The grade is chosen now but applied at develop
    /// time, so the look can be tuned between the shot and the reveal.
    func add(_ image: UIImage, grade: Grade) {
        guard let data = image.jpegData(compressionQuality: 0.92) else { return }
        let shot = Shot(id: UUID(), capturedAt: Date(), gradeID: grade.id,
                        file: "\(UUID().uuidString).jpg", developed: false, dropped: false)
        do {
            try data.write(to: url(for: shot), options: .atomic)
            shots.append(shot)
            save()
            scheduleDevelopNotification()
        } catch {
            // A failed write must not leave an index entry pointing at nothing.
        }
    }

    // MARK: Developing

    func develop() async {
        guard !developing else { return }
        developing = true
        defer { developing = false }

        let pending = readyToDevelop
        guard !pending.isEmpty else { return }

        var done: [Shot] = []
        for shot in pending {
            let target = url(for: shot)
            guard let raw = UIImage(contentsOfFile: target.path),
                  let ci = CIImage(image: raw) else { continue }

            // Develop in place: the graded frame replaces the raw one, so there
            // is never a second copy of the week sitting in Documents.
            if let out = shot.grade.render(ci), let data = out.jpegData(compressionQuality: 0.94) {
                try? data.write(to: target, options: .atomic)
            }
            if let i = shots.firstIndex(where: { $0.id == shot.id }) {
                shots[i].developed = true
                done.append(shots[i])
            }
        }
        save()
        justDeveloped = done.sorted { $0.capturedAt < $1.capturedAt }
    }

    /// Flagged once a frame has gone to the class wall, so the drop sheet can
    /// stop offering the same frame every Saturday.
    func markDropped(_ shot: Shot) {
        guard let i = shots.firstIndex(where: { $0.id == shot.id }) else { return }
        shots[i].dropped = true
        save()
    }

    /// Developed frames that haven't been put on the class wall yet.
    var droppable: [Shot] { developed.filter { !$0.isDropped } }

    func delete(_ shot: Shot) {
        try? fm.removeItem(at: url(for: shot))
        shots.removeAll { $0.id == shot.id }
        save()
    }

    // MARK: Persistence

    private func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([Shot].self, from: data) else { return }
        // Drop entries whose file vanished (offloaded app, restored backup).
        shots = decoded.filter { fm.fileExists(atPath: directory.appendingPathComponent($0.file).path) }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(shots) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }
}

// MARK: - The schedule

extension RollStore {
    /// Saturday 6:40pm local — "the color of 6:40pm in the South."
    nonisolated static let developHour = 18
    nonisolated static let developMinute = 40

    /// The next develop moment at or after `date`. If it's Saturday and 6:40 has
    /// not passed yet, that's today; otherwise the coming Saturday.
    ///
    /// nonisolated because the class wall groups every frame by this exact
    /// moment (see `ClassRoll.weekStart`) from plain value types.
    nonisolated static func developDate(for date: Date) -> Date {
        var cal = Calendar.current
        cal.firstWeekday = 1
        var comps = DateComponents()
        comps.weekday = 7                     // Saturday
        comps.hour = developHour
        comps.minute = developMinute
        comps.second = 0

        // `nextDate` with .strict never returns `date` itself, so a roll shot at
        // exactly 6:40 on a Saturday would otherwise jump a full week.
        if let next = cal.nextDate(after: date.addingTimeInterval(-1), matching: comps,
                                   matchingPolicy: .nextTime, direction: .forward) {
            return next
        }
        return date
    }

    var nextDevelop: Date {
        let now = Date()
        return undeveloped
            .map { Self.developDate(for: $0.capturedAt) }
            .filter { $0 > now }
            .min() ?? Self.developDate(for: now)
    }

    /// One local notification, replaced each time a frame is added.
    func scheduleDevelopNotification() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }
            Task { @MainActor in
                let count = self.undeveloped.count
                guard count > 0 else { return }

                let content = UNMutableNotificationContent()
                content.title = "YOUR ROLL IS READY"
                content.body = count == 1
                    ? "One frame from this week just developed."
                    : "\(count) frames from this week just developed."
                content.sound = .default
                content.userInfo = ["route": "ianroyz://roll"]

                let fire = self.nextDevelop
                let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)

                center.removePendingNotificationRequests(withIdentifiers: ["roll.develop"])
                try? await center.add(UNNotificationRequest(identifier: "roll.develop", content: content, trigger: trigger))
            }
        }
    }

    func requestNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            Task { @MainActor in self.scheduleDevelopNotification() }
        }
    }
}

// MARK: - Countdown

/// Ticks once a second toward the next develop. Used by the sealed-roll card.
@MainActor
final class DevelopClock: ObservableObject {
    @Published var remaining: TimeInterval = 0
    private var timer: Timer?

    func start(target: Date) {
        stop()
        tick(target)
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick(target) }
        }
    }
    func stop() { timer?.invalidate(); timer = nil }
    private func tick(_ target: Date) { remaining = max(0, target.timeIntervalSinceNow) }

    var parts: (d: Int, h: Int, m: Int, s: Int) {
        let t = Int(remaining)
        return (t / 86_400, (t / 3600) % 24, (t / 60) % 60, t % 60)
    }
}
