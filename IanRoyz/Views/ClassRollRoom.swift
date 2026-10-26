import SwiftUI

// MARK: - THE SATURDAY WALL · the open wall
//
// The gallery side of THE ROLL: every classmate's Saturday, stacked one volume
// per week, running to graduation. A volume that hasn't developed is not drawn —
// `ClassRoll.volumes` filters those out before this file ever sees them.

struct ClassRollRoom: View {
    @ObservedObject private var wall = ClassRoll.shared
    @ObservedObject private var roll = RollStore.shared
    @ObservedObject private var live = Live.shared
    @State private var selected: Drop?
    @State private var dropping = false
    @State private var showRoster = false

    var body: some View {
        Group {
            if wall.isMember, let info = wall.info {
                gallery(info)
            } else {
                JoinClassView()
            }
        }
        .background(Ink.night)
        .roomBack()
        .fullScreenCover(item: $selected) { drop in
            DropViewer(drop: drop)
        }
        .sheet(isPresented: $dropping) { DropSheet() }
        .sheet(isPresented: $showRoster) { RosterView() }
        .task { await wall.refresh() }
        // Same convention as -ROOM / -SEEDROLL: the sheets in this room are
        // behind a tap on a device, and there is no tap in the simulator.
        // `-CLASSSHEET drop|frame|roster`. Debug arg only.
        .onAppear {
            let args = ProcessInfo.processInfo.arguments
            guard let i = args.firstIndex(of: "-CLASSSHEET"), i + 1 < args.count else { return }
            switch args[i + 1] {
            case "drop":
                // The sheet needs developed frames, and -DEVELOPNOW normally
                // only runs from inside THE ROLL.
                Task {
                    if roll.forceDevelop && !roll.undeveloped.isEmpty { await roll.develop() }
                    roll.justDeveloped = []
                    dropping = true
                }
            case "frame":  selected = wall.volumes.first?.drops.first
            case "roster": showRoster = true
            default: break
            }
        }
    }

    private func gallery(_ info: ClassInfo) -> some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 26, pinnedViews: []) {
                ClassHeader(info: info) { showRoster = true }

                // The class's own prompt wins; the live feed is how a week gets
                // a theme before anybody is running a server.
                if let prompt = info.prompt ?? live.copy.classPrompt {
                    PromptCard(prompt: prompt, guest: live.copy.guestName, handle: live.copy.guestHandle)
                }

                DuoRollCard(prompt: info.prompt ?? live.copy.classPrompt ?? "Shoot your week")

                if !wall.festivalPicks.isEmpty {
                    FestivalShelf(drops: wall.festivalPicks) { selected = $0 }
                }

                if !roll.droppable.isEmpty {
                    dropBanner
                }

                if wall.volumes.isEmpty {
                    emptyWall(info)
                } else {
                    ForEach(wall.volumes) { volume in
                        VolumeSection(volume: volume, total: info.totalWeeks) { selected = $0 }
                    }
                }

                Kicker(text: "\(wall.volumes.count) volumes · \(wall.drops.count) frames kept in time",
                       color: .white.opacity(0.4), size: 9)
                    .padding(.top, 8)
                    .padding(.bottom, 44)
            }
            .padding(.horizontal, 18)
        }
        .refreshable { await wall.refresh() }
    }

    /// The only push in the room, and it only exists in the window where you
    /// actually have developed frames nobody has seen.
    private var dropBanner: some View {
        Button { dropping = true } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(.black.opacity(0.12)).frame(width: 42, height: 42)
                    Image(systemName: "arrow.up.to.line")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.black)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(roll.droppable.count) FRAME\(roll.droppable.count == 1 ? "" : "S") DEVELOPED")
                        .font(.mono(10, .heavy)).tracking(1.6)
                        .foregroundStyle(.black.opacity(0.65))
                    Text("PUT THEM ON THE WALL")
                        .font(.display(20))
                        .foregroundStyle(.black)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(.black)
            }
            .padding(16)
            .background(Ink.gold, in: RoundedRectangle(cornerRadius: 22))
        }
        .buttonStyle(.plain)
    }

    private func emptyWall(_ info: ClassInfo) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "square.grid.3x3")
                .font(.system(size: 26))
                .foregroundStyle(Ink.gold.opacity(0.8))
            Text("NOTHING DEVELOPED YET")
                .font(.display(26))
                .foregroundStyle(.white)
            Text("The wall fills Saturday at 6:40, all at once. Shoot your week — everybody's frames land in the same minute.")
                .font(.body_(13))
                .foregroundStyle(Ink.mist)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
        }
        .padding(.vertical, 46)
        .frame(maxWidth: .infinity)
        .background(Ink.charcoal, in: RoundedRectangle(cornerRadius: 26))
        .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(Ink.gold.opacity(0.2)))
    }
}

// MARK: - The header · who this class is and how far in it is

private struct ClassHeader: View {
    let info: ClassInfo
    let onRoster: () -> Void
    @ObservedObject private var wall = ClassRoll.shared

    var body: some View {
        VStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Kicker(text: "The Open Community", color: Ink.goldDeep)
                Text("THE SATURDAY\nWALL")
                    .font(.display(38))
                    .foregroundStyle(Ink.gold)
                    .minimumScaleFactor(0.55)
                    .lineLimit(2)
                Text("everybody's week, opened in the same moment.")
                    .font(.displayItal(15))
                    .foregroundStyle(Ink.mist)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            CommunityMeter()

            HStack(spacing: 10) {
                Stat(value: "\(wall.drops.count)", label: "FRAMES")
                Stat(value: "\(wall.classmates.count)", label: "SHOOTING")
                Stat(value: "\(wall.streak)", label: "YOUR STREAK", gold: wall.streak > 0)
            }

            Button(action: onRoster) {
                HStack(spacing: 12) {
                    HStack(spacing: -8) {
                        ForEach(Array(wall.classmates.prefix(5)), id: \.id) { mate in
                            AvatarBubble(file: mate.avatar,
                                         initials: ClassRoll.initials(name: mate.name, handle: mate.handle), size: 30)
                                .overlay(Circle().strokeBorder(Ink.night, lineWidth: 2))
                        }
                    }
                    Text(wall.classmates.isEmpty ? "BE THE FIRST ONE HERE" : "THE PEOPLE")
                        .font(.mono(9, .bold)).tracking(1.6)
                        .foregroundStyle(Ink.gold)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Ink.gold)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 12)
    }
}

/// The public wall grows by volume rather than by a school calendar.
struct CommunityMeter: View {
    @ObservedObject private var wall = ClassRoll.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text("VOL. \(String(format: "%02d", max(1, wall.volumes.count)))")
                    .font(.mono(11, .heavy)).tracking(2)
                    .foregroundStyle(Ink.gold)
                Text("OPEN ARCHIVE")
                    .font(.mono(11, .medium)).tracking(2)
                    .foregroundStyle(.white.opacity(0.45))
                Spacer()
                Text("SATURDAY 6:40 CT")
                    .font(.mono(9, .bold)).tracking(1.8)
                    .foregroundStyle(.white.opacity(0.45))
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.10)).frame(height: 6)
                    Capsule().fill(LinearGradient(colors: [Ink.goldDeep, Ink.gold],
                                                    startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(6, geo.size.width * 0.72), height: 6)
                    Circle()
                        .fill(Ink.gold)
                        .frame(width: 10, height: 10)
                        .offset(x: geo.size.width - 10)
                        .opacity(0.7)
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 12)
        }
        .padding(16)
        .background(Ink.charcoal, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.08)))
    }
}

private struct Stat: View {
    let value: String
    let label: String
    var gold: Bool = false
    var body: some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.display(24))
                .foregroundStyle(gold ? Ink.gold : .white)
            Text(label)
                .font(.mono(7.5, .bold)).tracking(1.2)
                .foregroundStyle(.white.opacity(0.45))
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct PromptCard: View {
    let prompt: String
    var guest: String?
    var handle: String?
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "quote.opening")
                .font(.system(size: 14))
                .foregroundStyle(Ink.gold)
            VStack(alignment: .leading, spacing: 2) {
                Kicker(text: "This week everybody shoots", color: .white.opacity(0.5), size: 8)
                Text(prompt.uppercased())
                    .font(.display(22))
                    .foregroundStyle(.white)
                if let guest {
                    Text("DIRECTED THIS WEEK BY \(guest.uppercased())\(handle.map { " · @\($0)" } ?? "")")
                        .font(.mono(7.5, .bold)).tracking(1)
                        .foregroundStyle(Ink.gold.opacity(0.85))
                }
            }
            Spacer()
        }
        .padding(16)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Ink.gold.opacity(0.22)))
    }
}

/// The monthly shelf is intentionally small: it celebrates a few frames people
/// kept without turning the wall into a ranked feed.
private struct FestivalShelf: View {
    let drops: [Drop]
    let onOpen: (Drop) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Kicker(text: "THE ONE-FRAME FESTIVAL", color: Ink.goldDeep, size: 8)
                Spacer()
                Text("THIS MONTH")
                    .font(.mono(7.5, .bold)).tracking(1.2)
                    .foregroundStyle(.white.opacity(0.4))
            }
            Text("THREE FRAMES PEOPLE HELD ONTO.")
                .font(.display(19))
                .foregroundStyle(.white)
            HStack(spacing: 7) {
                ForEach(drops) { drop in
                    Button { onOpen(drop) } label: {
                        DropCell(drop: drop)
                            .frame(maxWidth: .infinity)
                            .scaleEffect(0.78, anchor: .top)
                            .frame(height: 166, alignment: .top)
                            .clipped()
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(Ink.charcoal, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Ink.gold.opacity(0.2)))
    }
}

/// Two people can carry the same prompt without being locked into a private
/// group. The invite is the connection; both weeks still belong to the open
/// archive when Saturday arrives.
private struct DuoRollCard: View {
    let prompt: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "link")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.black)
                .frame(width: 42, height: 42)
                .background(Ink.gold, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Kicker(text: "DUO ROLL", color: Ink.gold, size: 8)
                Text("SHOOT THIS ONE WITH SOMEONE")
                    .font(.display(18))
                    .foregroundStyle(.white)
                Text("Same prompt. Two perspectives. One Saturday reveal.")
                    .font(.body_(11.5))
                    .foregroundStyle(Ink.mist)
            }
            Spacer(minLength: 0)
            ShareLink(item: "I want to shoot this week's DUO ROLL with you: \(prompt). Join me on THE SATURDAY WALL — ianroyz://community") {
                Text("PASS")
                    .font(.mono(9, .bold)).tracking(1.4)
                    .foregroundStyle(.black)
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(Ink.gold, in: Capsule())
            }
        }
        .padding(15)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.1)))
    }
}

// MARK: - One Saturday

private struct VolumeSection: View {
    let volume: Volume
    let total: Int
    let onOpen: (Drop) -> Void

    private let cols = [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("VOL. \(String(format: "%02d", volume.number))")
                    .font(.mono(11, .heavy)).tracking(2)
                    .foregroundStyle(Ink.gold)
                Rectangle().fill(Ink.gold.opacity(0.25)).frame(height: 0.8)
                Text(ClassRoll.label(for: volume.week))
                    .font(.mono(9, .bold)).tracking(1.5)
                    .foregroundStyle(.white.opacity(0.5))
            }

            Text("\(volume.drops.count) FRAMES · \(volume.contributors) SHOOTER\(volume.contributors == 1 ? "" : "S")")
                .font(.mono(8, .semibold)).tracking(1.4)
                .foregroundStyle(.white.opacity(0.35))

            LazyVGrid(columns: cols, spacing: 6) {
                ForEach(volume.drops) { drop in
                    Button { onOpen(drop) } label: { DropCell(drop: drop) }
                        .buttonStyle(.plain)
                        // .reveal() belongs on the cells, never the section: a
                        // view taller than the viewport never reaches the
                        // identity phase, so a whole volume would sit at
                        // opacity 0 forever.
                        .reveal()
                }
            }
        }
    }
}

struct DropCell: View {
    let drop: Drop
    @ObservedObject private var wall = ClassRoll.shared
    @State private var ui: UIImage?

    var body: some View {
        ZStack(alignment: .bottom) {
            if let ui {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 210)
                    .clipped()
            } else {
                Ink.charcoal.frame(height: 210)
            }

            LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .center, endPoint: .bottom)

            HStack(spacing: 6) {
                AvatarBubble(file: drop.authorAvatar,
                             initials: ClassRoll.initials(name: drop.authorName, handle: drop.authorHandle), size: 20)
                Text("@\(drop.authorHandle)")
                    .font(.mono(8, .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer()
                if drop.keeps > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: drop.keptByMe ? "bookmark.fill" : "bookmark")
                            .font(.system(size: 8, weight: .bold))
                        Text("\(drop.keeps)").font(.mono(8, .bold))
                    }
                    .foregroundStyle(drop.keptByMe ? Ink.gold : .white.opacity(0.7))
                }
            }
            .padding(9)
        }
        .frame(height: 210)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .task(id: drop.id) { if ui == nil { ui = wall.image(for: drop) } }
    }
}

struct AvatarBubble: View {
    let file: String?
    let initials: String
    var size: CGFloat = 28
    @State private var ui: UIImage?

    var body: some View {
        ZStack {
            if let ui {
                Image(uiImage: ui).resizable().scaledToFill()
            } else {
                Circle().fill(Ink.charcoal)
                Text(initials)
                    .font(.mono(size * 0.34, .bold))
                    .foregroundStyle(Ink.gold)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .contentShape(Circle())
        .task(id: file) { if ui == nil { ui = ClassRoll.shared.avatarImage(named: file) } }
    }
}

// MARK: - One frame, full screen

struct DropViewer: View {
    let drop: Drop
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var wall = ClassRoll.shared
    @State private var ui: UIImage?
    @State private var noteText = ""
    @State private var reporting = false
    @State private var confirmDelete = false
    @FocusState private var writing: Bool

    /// Re-read from the store so keeps and notes stay live while it's open.
    private var live: Drop { wall.drops.first { $0.id == drop.id } ?? drop }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    if let ui {
                        Image(uiImage: ui)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                    } else {
                        Ink.charcoal.frame(height: 420)
                    }

                    VStack(alignment: .leading, spacing: 18) {
                        author
                        if let caption = live.caption {
                            Text(caption)
                                .font(.body_(15))
                                .foregroundStyle(.white)
                        }
                        actions
                        notes
                    }
                    .padding(20)
                    .padding(.bottom, 40)
                }
            }

            VStack {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
                Spacer()
            }
        }
        .task { ui = wall.image(for: drop) }
        .confirmationDialog("This frame", isPresented: $reporting, titleVisibility: .visible) {
            Button("Report it", role: .destructive) {
                wall.report(live, reason: "reported from the wall")
                dismiss()
            }
            Button("Block @\(live.authorHandle)", role: .destructive) {
                wall.block(live)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Blocking hides everything they've put on the wall, right away.")
        }
        .confirmationDialog("Take it down?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Take it down", role: .destructive) {
                wall.deleteMine(live)
                dismiss()
            }
            Button("Keep it up", role: .cancel) {}
        }
    }

    private var author: some View {
        HStack(spacing: 11) {
            AvatarBubble(file: live.authorAvatar,
                         initials: ClassRoll.initials(name: live.authorName, handle: live.authorHandle), size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text("@\(live.authorHandle)")
                    .font(.mono(12, .bold))
                    .foregroundStyle(.white)
                Text("\(live.grade.name) · \(ClassRoll.label(for: live.week))")
                    .font(.mono(9)).tracking(1)
                    .foregroundStyle(Ink.gold.opacity(0.85))
            }
            Spacer()
            Menu {
                if let ui {
                    ShareLink(item: Image(uiImage: ui),
                              preview: SharePreview("Shot on THE ROLL", image: Image(uiImage: ui))) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
                if wall.isMine(live) {
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Label("Take it down", systemImage: "trash")
                    }
                } else {
                    Button(role: .destructive) { reporting = true } label: {
                        Label("Report or block", systemImage: "exclamationmark.triangle")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(.white.opacity(0.1), in: Circle())
            }
        }
    }

    /// KEEP, not like. You are pulling somebody's frame into your own archive,
    /// and the count is how many people did.
    private var actions: some View {
        HStack(spacing: 10) {
            Button { wall.keep(live) } label: {
                HStack(spacing: 7) {
                    Image(systemName: live.keptByMe ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 12, weight: .bold))
                    Text(live.keeps == 0 ? "KEEP" : "\(live.keeps) KEPT")
                        .font(.mono(10, .bold)).tracking(1.6)
                }
                .foregroundStyle(live.keptByMe ? .black : .white)
                .padding(.horizontal, 18).padding(.vertical, 12)
                .background(live.keptByMe ? Ink.gold : Color.white.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)
            Spacer()
        }
    }

    private var notes: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !live.notes.isEmpty {
                Rectangle().fill(.white.opacity(0.08)).frame(height: 0.7)
                ForEach(live.notes) { note in
                    VStack(alignment: .leading, spacing: 3) {
                        Text("@\(note.authorHandle)")
                            .font(.mono(9, .bold))
                            .foregroundStyle(Ink.gold.opacity(0.9))
                        Text(note.text)
                            .font(.body_(14))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }
            }

            HStack(spacing: 10) {
                TextField("say something", text: $noteText, axis: .vertical)
                    .font(.body_(14))
                    .foregroundStyle(.white)
                    .tint(Ink.gold)
                    .focused($writing)
                    .lineLimit(1...3)
                    .onChange(of: noteText) { _, new in
                        if new.count > Note.limit { noteText = String(new.prefix(Note.limit)) }
                    }
                Button {
                    wall.addNote(noteText, to: live)
                    noteText = ""
                    writing = false
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(.black)
                        .frame(width: 30, height: 30)
                        .background(Ink.gold, in: Circle())
                }
                .disabled(noteText.trimmingCharacters(in: .whitespaces).isEmpty)
                .opacity(noteText.trimmingCharacters(in: .whitespaces).isEmpty ? 0.35 : 1)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
        }
    }
}

// MARK: - The roster

struct RosterView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var wall = ClassRoll.shared

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    if wall.isInCommunity {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Kicker(text: "Pass the roll", color: .white.opacity(0.5), size: 8)
                                Text("EVERYBODY\nGETS IN")
                                    .font(.display(30))
                                    .foregroundStyle(Ink.gold)
                            }
                            Spacer()
                            ShareLink(item: "Shoot the week with me. Join THE SATURDAY WALL on IAN ROYZ: ianroyz://community") {
                                Text("INVITE")
                                    .font(.mono(10, .bold)).tracking(1.8)
                                    .foregroundStyle(.black)
                                    .padding(.horizontal, 18).padding(.vertical, 11)
                                    .background(Ink.gold, in: Capsule())
                            }
                        }
                        .padding(16)
                        .background(Ink.charcoal, in: RoundedRectangle(cornerRadius: 20))
                    }

                    ForEach(Array(wall.classmates.enumerated()), id: \.element.id) { i, mate in
                        HStack(spacing: 12) {
                            Text(String(format: "%02d", i + 1))
                                .font(.mono(10)).foregroundStyle(Ink.goldDeep)
                            AvatarBubble(file: mate.avatar,
                                         initials: ClassRoll.initials(name: mate.name, handle: mate.handle), size: 36)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("@\(mate.handle)")
                                    .font(.mono(12, .bold)).foregroundStyle(.white)
                                Text(mate.name)
                                    .font(.body_(12)).foregroundStyle(.white.opacity(0.5))
                            }
                            Spacer()
                            Text("\(mate.count)")
                                .font(.display(18)).foregroundStyle(Ink.gold)
                            Text("FRAMES")
                                .font(.mono(7, .bold)).tracking(1)
                                .foregroundStyle(.white.opacity(0.35))
                        }
                        .padding(.vertical, 8)
                    }

                    if !wall.blocked.isEmpty {
                        Button { wall.unblockAll() } label: {
                            Text("UNBLOCK EVERYONE (\(wall.blocked.count))")
                                .font(.mono(9, .bold)).tracking(1.4)
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        .padding(.top, 18)
                    }
                }
                .padding(18)
            }
            .background(Ink.night)
            .navigationTitle("THE PEOPLE")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("DONE") { dismiss() }
                        .font(.mono(10, .bold))
                        .tint(Ink.gold)
                }
            }
            .toolbarBackground(Ink.night, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }
}
