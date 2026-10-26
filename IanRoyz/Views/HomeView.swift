import SwiftUI

// MARK: - Home · the daydream
struct HomeView: View {
    let onWatchIntro: () -> Void
    @Binding var requestedRoom: Room?
    @State private var path: [Room] = {
        // debug: launch straight into a room, e.g. -ROOM motion
        if let i = ProcessInfo.processInfo.arguments.firstIndex(of: "-ROOM"),
           i + 1 < ProcessInfo.processInfo.arguments.count {
            switch ProcessInfo.processInfo.arguments[i + 1] {
            case "motion": return [.motion]
            case "saturdays": return [.saturdays]
            case "rotation": return [.rotation]
            case "roll": return [.roll]
            case "class": return [.classRoll]
            case "lost": return [.lost]
            case "shoots": return [.shoots]
            default: return []
            }
        }
        return []
    }()

    /// Drives the ambient loop behind the module stack.
    @State private var modulesVisible = true
    @ObservedObject private var live = Live.shared

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // pinned: the sky stays still while everything scrolls over it
                    GeometryReader { g in
                        let minY = g.frame(in: .global).minY
                        SkyHero()
                            .offset(y: minY < 0 ? -minY : 0)
                    }
                    .frame(height: 700)
                    .zIndex(-1)
                    Marquee(items: live.copy.marquee ?? LiveCopy.bundled.marquee ?? [])
                        .padding(.vertical, 10)
                        .background(Ink.night)

                    VStack(spacing: 18) {
                        // THE ROLL leads: it is the one room that is different
                        // every week and the only one anybody else is in.
                        NavigationLink(value: Room.roll)     { RollCard() }.reveal()
                        NavigationLink(value: Room.saturdays){ SaturdaysCard() }.reveal()
                        NavigationLink(value: Room.lost)     { LostFilesCard() }.reveal()
                        NavigationLink(value: Room.rotation) { RotationCard() }
                            .frame(height: 210)
                            .reveal()
                        NavigationLink(value: Room.shoots)   { ShootsCard() }.reveal()
                        NavigationLink(value: Room.motion)   { MotionCard() }.reveal()
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 26)
                    .background(
                        // THE AVENGERS running under the modules — paused once it
                        // scrolls off, so it isn't decoding video nobody can see.
                        ZStack {
                            LoopingVideoLayer(resource: "motion_avengers", active: modulesVisible)
                            Color.black.opacity(0.82)
                        }
                        .clipped()
                        .onGeometryChange(for: Bool.self) { proxy in
                            let f = proxy.frame(in: .global)
                            return f.maxY > 0 && f.minY < UIScreen.main.bounds.height
                        } action: { modulesVisible = $0 }
                    )

                    IndexFooter(onWatchIntro: onWatchIntro)
                }
            }
            .background(Ink.night)
            .ignoresSafeArea(edges: .top)
            .navigationDestination(for: Room.self) { room in
                switch room {
                case .motion:    MotionView()
                case .saturdays: SaturdaysView()
                case .rotation:  RotationView()
                case .roll:      RollRoom()
                case .classRoll: ClassRollRoom()
                case .lost:      LostFilesView()
                case .shoots:    ShootsView()
                }
            }
        }
        .tint(Ink.gold)
        .onAppear(perform: openRequestedRoom)
        .onChange(of: requestedRoom) { _, _ in openRequestedRoom() }
    }

    private func openRequestedRoom() {
        guard let requestedRoom else { return }
        path = [requestedRoom]
        self.requestedRoom = nil
    }
}

enum Room: Hashable { case motion, saturdays, rotation, roll, classRoll, lost, shoots }

// MARK: - Sky hero (the DREAMING poster)
private struct SkyHero: View {
    // sampled from the poster's top edge so the join is invisible
    private let posterBlue = Color(red: 0.362, green: 0.515, blue: 0.686)

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(stops: [
                .init(color: Ink.skyDeep, location: 0),
                .init(color: posterBlue, location: 0.15),
                .init(color: posterBlue, location: 1),
            ], startPoint: .top, endPoint: .bottom)

            // the poster IS the hero — one continuous sky, no join
            GeometryReader { geo in
                if let ui = bundleImage("me_poster_tall") {
                    Image(uiImage: ui)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                }
            }

            // the name floats on the clouds
            VStack(spacing: 10) {
                Kicker(text: "·• Unapologetic Creative •·", color: Ink.gold, size: 10)
                Text("IAN ROYZ")
                    .font(.display(62))
                    .foregroundStyle(Ink.gold)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .shadow(color: Ink.skyDeep.opacity(0.65), radius: 16, y: 5)
            }
            .padding(.top, 72)

            VStack {
                Spacer()
                Kicker(text: "filmmaker · photographer · creative",
                       color: .white.opacity(0.95), size: 8.5)
                    .shadow(color: Ink.skyDeep.opacity(0.8), radius: 5)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 16)
            }

            Grain(opacity: 0.045)
        }
        .frame(height: 700)
        .clipped()
    }
}

// MARK: - Room cards
private struct CardChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: 26))
            .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(.white.opacity(0.12), lineWidth: 0.8))
    }
}

private struct CardLabel: View {
    let kicker: String
    let title: String
    let detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Kicker(text: kicker, color: Ink.gold, size: 9)
            Text(title)
                .font(.display(30))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            HStack(spacing: 8) {
                Text(detail)
                    .font(.mono(10))
                    .tracking(1)
                    .foregroundStyle(.white.opacity(0.75))
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Ink.gold)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [.black.opacity(0), .black.opacity(0.85)],
                           startPoint: .top, endPoint: .bottom)
        )
    }
}

private struct MotionCard: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            Photo(name: "poster_motion_avengers").frame(height: 240)
            CardLabel(kicker: "06 · The Films", title: "MOTION", detail: "\(Archive.films.count) FILMS · DIR. IAN ROYES")
        }
        .frame(height: 240)
        .modifier(CardChrome())
    }
}

private struct SaturdaysCard: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            Photo(name: "poster_sat_dirtysouth").frame(height: 240)
            CardLabel(kicker: "02 · The Series", title: "SATURDAYS", detail: "A SEASON OF NOTHING MUCH · EP.01 →")
        }
        .frame(height: 240)
        .modifier(CardChrome())
    }
}

private struct RotationCard: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            Photo(name: Archive.goldenPhoto).frame(height: 210)
            CardLabel(kicker: "04 · The Head", title: "IN ROTATION",
                      detail: "A FILM · A RECORD · A BOOK · A COLOR")
        }
        .frame(height: 210)
        .modifier(CardChrome())
    }
}

/// THE ROLL — the only card that changes on its own, and the only one with
/// other people in it. It carries live state on both halves: what's sealed on
/// this phone, and what the class has on the wall.
private struct RollCard: View {
    @ObservedObject private var roll = RollStore.shared
    @ObservedObject private var wall = ClassRoll.shared

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                Photo(name: "roll_cover").frame(height: 190)
                LinearGradient(colors: [.black.opacity(0.05), .black.opacity(0.9)],
                               startPoint: .top, endPoint: .bottom)

                VStack(alignment: .leading, spacing: 6) {
                    Kicker(text: "01 · The Camera", color: Ink.gold, size: 9)
                    Text("THE ROLL")
                        .font(.display(34))
                        .foregroundStyle(.white)
                    HStack(spacing: 6) {
                        Image(systemName: roll.isReady ? "sparkles" : "lock.fill")
                            .font(.system(size: 9, weight: .bold))
                        Text(status)
                            .font(.mono(9, .bold)).tracking(1)
                            .lineLimit(1).minimumScaleFactor(0.7)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Ink.gold)
                    }
                    .foregroundStyle(roll.isReady ? Ink.gold : .white.opacity(0.7))
                }
                .padding(16)
            }
            .frame(height: 190)

            // the open-wall line — the reason to come back on a Saturday
            HStack(spacing: 10) {
                if wall.isMember {
                    HStack(spacing: -7) {
                        ForEach(Array(wall.classmates.prefix(4)), id: \.id) { mate in
                            AvatarBubble(file: mate.avatar,
                                         initials: ClassRoll.initials(name: mate.name, handle: mate.handle), size: 22)
                                .overlay(Circle().strokeBorder(Ink.charcoal, lineWidth: 1.5))
                        }
                    }
                }
                Text(classLine)
                    .font(.mono(8.5, .semibold)).tracking(1.1)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1).minimumScaleFactor(0.65)
                Spacer()
                Text(wall.isInCommunity ? "THE WALL" : "ENTER THE WALL")
                    .font(.mono(8.5, .bold)).tracking(1.2)
                    .foregroundStyle(Ink.gold)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .background(Ink.charcoal)
        }
        .modifier(CardChrome())
    }

    private var status: String {
        if roll.isReady { return "READY TO DEVELOP" }
        let n = roll.undeveloped.count
        return n == 0 ? "SHOOT THE WEEK · DEVELOPS SATURDAY 6:40" : "\(n) SEALED · DEVELOPS SATURDAY 6:40"
    }

    private var classLine: String {
        guard wall.isInCommunity else { return "THE SATURDAY WALL IS OPEN" }
        if wall.drops.isEmpty { return "BE HERE FOR THE FIRST REVEAL" }
        return "\(wall.drops.count) FRAMES · \(wall.volumes.count) VOLUMES"
    }
}

private struct LostFilesCard: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            Photo(name: Archive.darkPhoto).frame(height: 200)
                .overlay(Color.black.opacity(0.25))
            // scanlines
            VStack(spacing: 5) {
                ForEach(0..<24, id: \.self) { _ in
                    Rectangle().fill(.white.opacity(0.045)).frame(height: 1)
                }
            }
            CardLabel(kicker: "03 · The Vault", title: "LOST FILES", detail: "VOL.1 · 6 FILES · RECOVERED 05.23.26")
        }
        .frame(height: 200)
        .modifier(CardChrome())
    }
}

private struct ShootsCard: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            HStack(spacing: 2) {
                Photo(name: "shoot_soft_DSC04984")
                Photo(name: "shoot_joshcar_DSC07933")
                Photo(name: "shoot_mediaday_DSC04882")
            }
            .frame(height: 230)
            CardLabel(kicker: "05 · The Photographs", title: "SHOOTS", detail: "EXPERIMENTS · @ROYZFILMZ")
        }
        .frame(height: 230)
        .modifier(CardChrome())
    }
}

// MARK: - Footer · THE INDEX
private struct IndexFooter: View {
    @Environment(\.openURL) private var openURL
    let onWatchIntro: () -> Void
    var body: some View {
        VStack(spacing: 26) {
            Rectangle().fill(Ink.gold.opacity(0.25)).frame(height: 0.8)

            Kicker(text: "The Index", color: Ink.gold)

            VStack(spacing: 12) {
                ForEach(Archive.links, id: \.0) { link in
                    Button {
                        if let url = URL(string: link.2) { openURL(url) }
                    } label: {
                        HStack {
                            Text(link.0).font(.mono(11, .bold)).tracking(2).foregroundStyle(.white)
                            Spacer()
                            Text(link.1).font(.displayItal(14)).foregroundStyle(Ink.mist)
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Ink.gold)
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.08)))
                    }
                }
            }
            .padding(.horizontal, 18)

            Button(action: onWatchIntro) {
                HStack(spacing: 9) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 9, weight: .bold))
                    Text("WATCH THE INTRO")
                        .font(.mono(10, .bold))
                        .tracking(1.8)
                }
                .foregroundStyle(Ink.gold)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(Ink.gold.opacity(0.09), in: Capsule())
                .overlay(Capsule().strokeBorder(Ink.gold.opacity(0.35)))
            }

            Button {
                if let url = URL(string: "https://royzmediagroup.com/#book") { openURL(url) }
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Kicker(text: "Royz Media Group", color: Ink.gold, size: 8)
                    HStack(alignment: .firstTextBaseline) {
                        Text("MAKE SOMETHING")
                            .font(.display(22))
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 13, weight: .bold))
                    }
                    Text("Need a film, photos, or an app that feels like yours?")
                        .font(.displayItal(12))
                        .foregroundStyle(Ink.mist)
                }
                .foregroundStyle(.white)
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    LinearGradient(colors: [Ink.skyDeep.opacity(0.8), Ink.charcoal],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 20)
                )
                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Ink.gold.opacity(0.3)))
            }
            .padding(.horizontal, 18)

            VStack(spacing: 6) {
                Text("shot & cut by ian royes")
                    .font(.displayItal(13))
                    .foregroundStyle(Ink.mist)
                Kicker(text: "© 2026 · Unapologetic creative", color: .white.opacity(0.35), size: 8)
            }
            .padding(.bottom, 46)
        }
        .padding(.top, 30)
        .background(Ink.night)
    }
}
