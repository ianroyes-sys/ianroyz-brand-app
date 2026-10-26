import SwiftUI

// MARK: - THE ROLL · the room
//
// Three states, and the room is only interesting because it refuses to show you
// the middle one: SEALED (frames in, nothing visible) → READY (6:40 has passed)
// → the developed grid. Never render an undeveloped frame here.

struct RollRoom: View {
    @ObservedObject private var roll = RollStore.shared
    @ObservedObject private var wall = ClassRoll.shared
    @StateObject private var clock = DevelopClock()
    @State private var shooting = false
    @State private var revealing = false
    @State private var dropping = false
    @State private var revealIndex = 0

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 26) {
                RollIdentity()
                    .padding(.top, 12)

                RoomHeader(kicker: "Shoot the week · see it Saturday", title: "THE ROLL",
                           subtitle: "a disposable that develops at 6:40.")

                if roll.isReady {
                    readyCard
                } else {
                    sealedCard
                }

                shootButton

                // The open wall is one tap from the sealed roll: your week and
                // everybody else's reveal belong to the same ritual.
                ClassStrip { dropping = true }

                if !roll.developed.isEmpty {
                    developedGrid
                }

                Kicker(text: "nothing opens early. that's the point.",
                       color: .white.opacity(0.4), size: 9)
                    .padding(.bottom, 40)
            }
            .padding(.horizontal, 18)
        }
        .background(Ink.night)
        .roomBack()
        .fullScreenCover(isPresented: $shooting) { RollCameraView() }
        .sheet(isPresented: $dropping) { DropSheet() }
        .fullScreenCover(isPresented: $revealing) {
            // The reveal hands straight off to the wall: the frames are new, the
            // Saturday is live, and this is the one minute the drop makes sense.
            RevealView(shots: roll.justDeveloped) {
                revealing = false
                roll.justDeveloped = []
                guard wall.isMember, !roll.droppable.isEmpty else { return }
                // A sheet raised in the same frame the cover is dismissing gets
                // swallowed — let the dismissal finish first.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { dropping = true }
            }
        }
        // Notification permission is asked for after the first frame is shot
        // (see RollCameraView) — not on arrival. Prompting someone who hasn't
        // shot anything yet burns the one ask you get for a roll that's empty.
        .onAppear {
            clock.start(target: roll.nextDevelop)
            // `-DEVELOPNOW` runs the whole develop → reveal path without waiting
            // for Saturday. Debug arg only; a shipped launch never carries it.
            if roll.forceDevelop && !roll.undeveloped.isEmpty {
                Task {
                    await roll.develop()
                    if !roll.justDeveloped.isEmpty { revealing = true }
                }
            }
        }
        .onDisappear { clock.stop() }
    }

    // MARK: Sealed — the waiting state, and the one that has to feel good

    private var sealedCard: some View {
        VStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 26)
                    .fill(LinearGradient(colors: [Ink.charcoal, Ink.night],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                RoundedRectangle(cornerRadius: 26)
                    .strokeBorder(Ink.gold.opacity(0.25), lineWidth: 1)

                VStack(spacing: 14) {
                    Image(systemName: roll.undeveloped.isEmpty ? "camera.aperture" : "lock.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(Ink.gold.opacity(0.85))

                    Text(roll.undeveloped.isEmpty ? "NOTHING SHOT YET" : "\(roll.undeveloped.count) SEALED")
                        .font(.display(30))
                        .foregroundStyle(.white)

                    if roll.undeveloped.isEmpty {
                        Text("Shoot anything. You won't see it until Saturday.")
                            .font(.body_(13))
                            .foregroundStyle(Ink.mist)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 30)
                    } else {
                        countdown
                    }
                }
                .padding(.vertical, 38)
            }
            .frame(minHeight: 240)
        }
    }

    private var countdown: some View {
        VStack(spacing: 7) {
            Kicker(text: "Develops in", color: .white.opacity(0.45), size: 9)
            HStack(spacing: 5) {
                unit(clock.parts.d, "D")
                unit(clock.parts.h, "H")
                unit(clock.parts.m, "M")
                unit(clock.parts.s, "S")
            }
        }
    }

    private func unit(_ v: Int, _ label: String) -> some View {
        HStack(spacing: 1) {
            Text(String(format: "%02d", v))
                .font(.mono(21, .bold))
                .foregroundStyle(Ink.gold)
                .monospacedDigit()
            Text(label)
                .font(.mono(9, .bold))
                .foregroundStyle(.white.opacity(0.4))
        }
        .padding(.horizontal, 3)
    }

    // MARK: Ready

    private var readyCard: some View {
        Button {
            Task {
                await roll.develop()
                if !roll.justDeveloped.isEmpty { revealing = true }
            }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 26).fill(Ink.gold)
                VStack(spacing: 10) {
                    Kicker(text: "Saturday · 6:40", color: .black.opacity(0.55))
                    Text(roll.developing ? "DEVELOPING…" : "DEVELOP \(roll.readyToDevelop.count)")
                        .font(.display(34))
                        .foregroundStyle(.black)
                    Text("your week, all at once")
                        .font(.displayItal(13))
                        .foregroundStyle(.black.opacity(0.65))
                }
                .padding(.vertical, 40)
            }
            .frame(minHeight: 200)
        }
        .buttonStyle(.plain)
        .disabled(roll.developing)
    }

    private var shootButton: some View {
        Button { shooting = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "camera.fill").font(.system(size: 13, weight: .bold))
                Text("SHOOT A FRAME").font(.mono(11, .bold)).tracking(2.6)
            }
            .foregroundStyle(roll.isReady ? .white : .black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(roll.isReady ? Color.white.opacity(0.12) : Ink.gold, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: Developed

    private let cols = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    private var developedGrid: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Kicker(text: "Developed")
                Spacer()
                Text("\(roll.developed.count)")
                    .font(.mono(10, .bold))
                    .foregroundStyle(Ink.gold)
            }
            LazyVGrid(columns: cols, spacing: 10) {
                ForEach(roll.developed) { shot in
                    DevelopedCell(shot: shot)
                }
            }
        }
        .padding(.top, 6)
    }
}

// MARK: - Who's holding the camera
//
// The room opens on a face, not a countdown. Before you've joined a class that
// face is Ian's — the roll is his idea and somebody has to be shooting first.

struct RollIdentity: View {
    @ObservedObject private var wall = ClassRoll.shared

    var body: some View {
        HStack(spacing: 13) {
            ZStack {
                if let me = wall.profile, let ui = wall.avatar(for: me) {
                    Image(uiImage: ui).resizable().scaledToFill()
                } else if let ui = bundleImage("roll_pfp") {
                    Image(uiImage: ui).resizable().scaledToFill()
                } else {
                    Ink.charcoal
                }
            }
            .frame(width: 58, height: 58)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(Ink.gold.opacity(0.8), lineWidth: 1.5))
            .contentShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(wall.profile?.display ?? "@notsoian")
                    .font(.mono(12, .bold))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.mono(8.5, .semibold)).tracking(1.2)
                    .foregroundStyle(Ink.gold)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer()
            if wall.streak > 0 {
                VStack(spacing: 1) {
                    Text("\(wall.streak)")
                        .font(.display(22))
                        .foregroundStyle(Ink.gold)
                    Text("WEEK\(wall.streak == 1 ? "" : "S")\nSTRAIGHT")
                        .font(.mono(6.5, .bold)).tracking(0.8)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
        }
        .padding(14)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(0.08)))
    }

    private var subtitle: String {
        if wall.isInCommunity { return "THE SATURDAY WALL · EVERYONE WELCOME" }
        return "SHOOTING SOLO · THE WALL IS OPEN"
    }
}

// MARK: - The wall, from inside the roll

struct ClassStrip: View {
    let onDrop: () -> Void
    @ObservedObject private var wall = ClassRoll.shared
    @ObservedObject private var roll = RollStore.shared

    var body: some View {
        VStack(spacing: 12) {
            if wall.isMember, wall.isInCommunity {
                NavigationLink(value: Room.classRoll) {
                    HStack(spacing: 13) {
                        ZStack {
                            if let latest = wall.latestVolume?.drops.first,
                               let ui = wall.image(for: latest) {
                                Image(uiImage: ui).resizable().scaledToFill()
                            } else {
                                Ink.charcoal
                            }
                        }
                        .frame(width: 62, height: 62)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .contentShape(RoundedRectangle(cornerRadius: 14))

                        VStack(alignment: .leading, spacing: 4) {
                            Kicker(text: "The Saturday Wall", color: Ink.gold, size: 8)
                            Text(wall.drops.isEmpty ? "NOTHING UP YET" : "\(wall.drops.count) FRAMES ON THE WALL")
                                .font(.display(19))
                                .foregroundStyle(.white)
                                .lineLimit(1).minimumScaleFactor(0.7)
                            Text("\(wall.volumes.count) VOLUMES · OPENS EVERY SATURDAY")
                                .font(.mono(7.5, .semibold)).tracking(1)
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Ink.gold)
                    }
                    .padding(14)
                    .background(Ink.charcoal, in: RoundedRectangle(cornerRadius: 22))
                    .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Ink.gold.opacity(0.22)))
                }
                .buttonStyle(.plain)

                if !roll.droppable.isEmpty {
                    Button(action: onDrop) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.up.to.line")
                                .font(.system(size: 12, weight: .bold))
                            Text("ADD \(roll.droppable.count) TO THE WALL")
                                .font(.mono(10, .bold)).tracking(1.8)
                        }
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Ink.gold, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            } else {
                NavigationLink(value: Room.classRoll) {
                    HStack(spacing: 13) {
                        Image(systemName: "globe.americas.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(Ink.gold)
                            .frame(width: 40, height: 40)
                            .background(.white.opacity(0.08), in: Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text("SHOOT IT WITH EVERYBODY")
                                .font(.display(19))
                                .foregroundStyle(.white)
                                .lineLimit(1).minimumScaleFactor(0.7)
                            Text("one open wall · one Saturday reveal")
                                .font(.body_(12))
                                .foregroundStyle(Ink.mist)
                                .lineLimit(1).minimumScaleFactor(0.7)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Ink.gold)
                    }
                    .padding(14)
                    .background(Ink.charcoal, in: RoundedRectangle(cornerRadius: 22))
                    .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Ink.gold.opacity(0.22)))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - One developed frame

struct DevelopedCell: View {
    let shot: Shot
    @ObservedObject private var roll = RollStore.shared
    @State private var full: UIImage?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let ui = full {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 200)
                    .clipped()
            } else {
                Ink.charcoal.frame(height: 200)
            }

            LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(shot.grade.name)
                        .font(.mono(8, .bold)).tracking(1.2)
                        .foregroundStyle(Ink.gold)
                    HStack(spacing: 5) {
                        Text(shot.capturedAt, format: .dateTime.month(.abbreviated).day())
                            .font(.mono(8))
                            .foregroundStyle(.white.opacity(0.6))
                        if shot.isDropped {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(Ink.gold.opacity(0.8))
                        }
                    }
                }
                Spacer()
                if let ui = full {
                    // Every developed frame is shareable — the reveal is the
                    // moment worth posting, so the button lives right on it.
                    ShareLink(item: Image(uiImage: ui),
                              preview: SharePreview("Shot on IAN ROYZ · \(shot.grade.name)",
                                                    image: Image(uiImage: ui))) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(7)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                }
            }
            .padding(10)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .task { full = roll.image(for: shot) }
    }
}

// MARK: - The reveal
//
// Frames come back one at a time, oldest first, so the week replays in order
// instead of arriving as a grid you scroll past.

struct RevealView: View {
    let shots: [Shot]
    let done: () -> Void

    @ObservedObject private var roll = RollStore.shared
    @State private var index = 0
    @State private var shown: UIImage?
    @State private var appeared = false
    @State private var shareCard: URL?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let ui = shown {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFit()
                    .ignoresSafeArea()
                    .opacity(appeared ? 1 : 0)
                    .scaleEffect(appeared ? 1 : 1.04)
            }

            VStack {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Kicker(text: "Saturday Premiere", color: Ink.gold)
                        Text("\(index + 1) / \(shots.count)")
                            .font(.mono(13, .bold))
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    Button(action: done) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                Spacer()

                if let ui = shown {
                    HStack(spacing: 12) {
                        if let shareCard {
                            ShareLink(item: shareCard,
                                      preview: SharePreview("My week on IAN ROYZ", image: Image(uiImage: ui))) {
                                Label("SHARE THE WEEK", systemImage: "square.and.arrow.up")
                                    .font(.mono(10, .bold))
                                    .foregroundStyle(.black)
                                    .padding(.horizontal, 20).padding(.vertical, 13)
                                    .background(Ink.gold, in: Capsule())
                            }
                        } else {
                            ShareLink(item: Image(uiImage: ui),
                                      preview: SharePreview("Shot on IAN ROYZ", image: Image(uiImage: ui))) {
                                Label("SHARE", systemImage: "square.and.arrow.up")
                                    .font(.mono(10, .bold))
                                    .foregroundStyle(.black)
                                    .padding(.horizontal, 20).padding(.vertical, 13)
                                    .background(Ink.gold, in: Capsule())
                            }
                        }

                        Button(action: next) {
                            Text(index + 1 >= shots.count ? "DONE" : "NEXT")
                                .font(.mono(10, .bold)).tracking(2)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 24).padding(.vertical, 13)
                                .background(.white.opacity(0.14), in: Capsule())
                        }
                    }
                    .padding(.bottom, 44)
                }
            }
        }
        .statusBarHidden()
        .task {
            load()
            shareCard = RevealCard.make(for: shots, store: roll)
        }
    }

    private func load() {
        guard index < shots.count else { done(); return }
        appeared = false
        shown = roll.image(for: shots[index])
        withAnimation(.easeOut(duration: 0.7)) { appeared = true }
    }

    private func next() {
        if index + 1 >= shots.count { done(); return }
        index += 1
        load()
    }
}
