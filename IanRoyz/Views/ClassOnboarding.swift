import SwiftUI
import PhotosUI

// MARK: - Getting onto the open wall
//
// A face and a handle are enough. THE SATURDAY WALL has no school, cohort, or
// code to clear — anyone who agrees to the rules can add their week.

struct JoinClassView: View {
    @ObservedObject private var wall = ClassRoll.shared
    @State private var step = 0

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 26) {
                RoomHeader(kicker: "The Open Community", title: "THE SATURDAY\nWALL",
                           subtitle: "one week, one reveal, everybody welcome.")
                    .padding(.top, 12)

                CoverCard()

                if step == 0 || wall.profile == nil {
                    ProfileStep { step = 1 }
                } else {
                    CommunityStep()
                }

                HowItWorks()
                    .padding(.bottom, 44)
            }
            .padding(.horizontal, 18)
        }
        .onAppear {
            if wall.profile != nil {
                step = 1
                Task { await wall.enterCommunity() }
            }
        }
    }
}

/// The room's face. Same frame as the card on the home screen, so arriving here
/// feels like the same place.
struct CoverCard: View {
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Photo(name: "roll_cover").frame(height: 190)
            LinearGradient(colors: [.black.opacity(0.1), .black.opacity(0.9)],
                           startPoint: .top, endPoint: .bottom)
            HStack(spacing: 12) {
                Image(uiImage: bundleImage("roll_pfp") ?? UIImage())
                    .resizable()
                    .scaledToFill()
                    .frame(width: 54, height: 54)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Ink.gold, lineWidth: 1.5))
                VStack(alignment: .leading, spacing: 2) {
                    Text("THE ROLL")
                        .font(.display(24))
                        .foregroundStyle(.white)
                    Text("shoot the week · see it Saturday")
                        .font(.mono(8, .semibold)).tracking(1.2)
                        .foregroundStyle(Ink.gold)
                }
            }
            .padding(16)
        }
        .frame(height: 190)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(.white.opacity(0.12)))
    }
}

// MARK: Step one · who you are

private struct ProfileStep: View {
    @ObservedObject private var wall = ClassRoll.shared
    let onDone: () -> Void

    @State private var handle = ""
    @State private var name = ""
    @State private var picked: PhotosPickerItem?
    @State private var avatar: UIImage?
    @State private var picking = false

    private var ready: Bool {
        handle.trimmingCharacters(in: .whitespaces).count >= 2 &&
        name.trimmingCharacters(in: .whitespaces).count >= 2
    }

    var body: some View {
        VStack(spacing: 18) {
            Kicker(text: "01 · Who's shooting", color: Ink.gold, size: 9)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button { picking = true } label: {
                ZStack {
                    if let avatar {
                        Image(uiImage: avatar).resizable().scaledToFill()
                    } else {
                        Circle().fill(.white.opacity(0.07))
                        VStack(spacing: 5) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(Ink.gold)
                            Text("A FACE")
                                .font(.mono(8, .bold)).tracking(1.4)
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }
                }
                .frame(width: 92, height: 92)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Ink.gold.opacity(0.5), lineWidth: 1))
                .contentShape(Circle())
            }
            .buttonStyle(.plain)

            Field(label: "HANDLE", text: $handle, prefix: "@", placeholder: "notsoian")
            Field(label: "NAME", text: $name, placeholder: "Ian Royes")

            Button {
                wall.createProfile(handle: handle, name: name, avatar: avatar)
                Task {
                    await wall.enterCommunity()
                    onDone()
                }
            } label: {
                Text("THAT'S ME")
                    .font(.mono(11, .bold)).tracking(2.4)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Ink.gold, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!ready)
            .opacity(ready ? 1 : 0.4)
        }
        .padding(20)
        .background(Ink.charcoal, in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(.white.opacity(0.08)))
        .photosPicker(isPresented: $picking, selection: $picked, matching: .images)
        .onChange(of: picked) { _, item in
            Task {
                guard let item, let data = try? await item.loadTransferable(type: Data.self) else { return }
                avatar = UIImage(data: data)
            }
        }
        .onAppear {
            handle = wall.profile?.handle ?? ""
            name = wall.profile?.name ?? ""
        }
    }
}

// MARK: Step two · enter the open wall

private struct CommunityStep: View {
    @ObservedObject private var wall = ClassRoll.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Kicker(text: "Your place is open", color: Ink.gold, size: 9)
            Text("YOUR WEEK\nBELONGS HERE.")
                .font(.display(30))
                .foregroundStyle(.white)
            Text("There is no code and no school list. Shoot during the week, choose what leaves your roll, and the wall opens on Saturday.")
                .font(.body_(14))
                .foregroundStyle(Ink.mist)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                Task { await wall.enterCommunity() }
            } label: {
                Text(wall.syncing ? "OPENING…" : wall.isInCommunity ? "YOU'RE ON THE WALL" : "ENTER THE WALL")
                    .font(.mono(11, .bold)).tracking(2.2)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Ink.gold, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(wall.syncing || wall.isInCommunity)

            if let error = wall.lastError {
                Text(error).font(.body_(12)).foregroundStyle(Ink.gold)
            }
        }
        .padding(20)
        .background(Ink.charcoal, in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Ink.gold.opacity(0.22)))
    }
}

// MARK: Legacy private-circle setup

private struct ClassStep: View {
    @ObservedObject private var wall = ClassRoll.shared
    @State private var code = ""
    @State private var starting = false
    @State private var className = ""
    @State private var newCode = ""
    @State private var gradYear = Calendar.current.component(.year, from: Date()) + 1

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Kicker(text: "02 · Which class", color: Ink.gold, size: 9)
                Spacer()
                if let me = wall.profile {
                    HStack(spacing: 7) {
                        AvatarBubble(file: me.avatarFile, initials: me.initials, size: 22)
                        Text(me.display).font(.mono(9, .bold)).foregroundStyle(.white.opacity(0.7))
                    }
                }
            }

            if starting {
                Field(label: "CLASS NAME", text: $className, placeholder: "The Class of 2027")
                Field(label: "JOIN CODE", text: $newCode, placeholder: "SPRING27", uppercase: true)

                HStack {
                    Text("GRADUATES")
                        .font(.mono(9, .bold)).tracking(1.4)
                        .foregroundStyle(.white.opacity(0.5))
                    Spacer()
                    Stepper("\(gradYear)", value: $gradYear, in: 2026...2036)
                        .fixedSize()
                        .tint(Ink.gold)
                        .foregroundStyle(.white)
                        .font(.mono(13, .bold))
                }

                Button {
                    Task {
                        await wall.create(name: className, code: newCode, graduation: graduationDate)
                    }
                } label: { primaryLabel("START THE CLASS") }
                    .buttonStyle(.plain)
                    .disabled(newCode.count < 3 || className.count < 3)
                    .opacity(newCode.count < 3 || className.count < 3 ? 0.4 : 1)

                Button { starting = false } label: {
                    Text("I HAVE A CODE")
                        .font(.mono(9, .bold)).tracking(1.6)
                        .foregroundStyle(.white.opacity(0.6))
                }
            } else {
                Field(label: "JOIN CODE", text: $code, placeholder: "SPRING27", uppercase: true)

                Button {
                    Task { await wall.join(code: code) }
                } label: { primaryLabel(wall.syncing ? "OPENING…" : "JOIN THE CLASS") }
                    .buttonStyle(.plain)
                    .disabled(code.count < 3 || wall.syncing)
                    .opacity(code.count < 3 ? 0.4 : 1)

                Button { starting = true } label: {
                    Text("OR START ONE")
                        .font(.mono(9, .bold)).tracking(1.6)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }

            if let err = wall.lastError {
                Text(err)
                    .font(.body_(12))
                    .foregroundStyle(Ink.gold.opacity(0.9))
            }
        }
        .padding(20)
        .background(Ink.charcoal, in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(.white.opacity(0.08)))
    }

    private var graduationDate: Date {
        var c = DateComponents()
        c.year = gradYear
        c.month = 5
        c.day = 15
        return Calendar.current.date(from: c) ?? Date()
    }

    private func primaryLabel(_ text: String) -> some View {
        Text(text)
            .font(.mono(11, .bold)).tracking(2.4)
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(Ink.gold, in: Capsule())
    }
}

private struct Field: View {
    let label: String
    @Binding var text: String
    var prefix: String? = nil
    var placeholder: String = ""
    var uppercase: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.mono(8, .bold)).tracking(1.6)
                .foregroundStyle(.white.opacity(0.45))
            HStack(spacing: 2) {
                if let prefix {
                    Text(prefix).font(.body_(16)).foregroundStyle(Ink.gold)
                }
                TextField(placeholder, text: $text)
                    .font(.body_(16))
                    .foregroundStyle(.white)
                    .tint(Ink.gold)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(uppercase ? .characters : .never)
                    .onChange(of: text) { _, new in
                        if uppercase { text = new.uppercased() }
                    }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
        }
    }
}

private struct HowItWorks: View {
    private let steps: [(String, String, String)] = [
        ("camera.aperture", "SHOOT ALL WEEK", "Frames seal the second you take them. Nobody sees anything — not even you."),
        ("lock.fill", "SATURDAY 6:40", "Everybody arrives at the same reveal. No early looks, no head start."),
        ("square.grid.3x3.fill", "THE WALL FILLS", "Weeks land together and stack as volumes anyone can return to."),
        ("sparkles", "THE ARCHIVE GROWS", "One Saturday at a time, a living contact sheet made by people everywhere."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Kicker(text: "How it runs", color: Ink.goldDeep)
            ForEach(steps, id: \.0) { step in
                HStack(alignment: .top, spacing: 13) {
                    Image(systemName: step.0)
                        .font(.system(size: 13))
                        .foregroundStyle(Ink.gold)
                        .frame(width: 24, height: 24)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(step.1)
                            .font(.mono(10, .bold)).tracking(1.4)
                            .foregroundStyle(.white)
                        Text(step.2)
                            .font(.body_(13))
                            .foregroundStyle(Ink.mist)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 22))
    }
}

// MARK: - Putting frames on the wall
//
// Developed frames only, chosen one by one. A roll never posts itself: the
// reveal is yours first, and what leaves it is a decision.

struct DropSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var wall = ClassRoll.shared
    @ObservedObject private var roll = RollStore.shared

    @State private var picked: Set<UUID> = []
    @State private var captions: [UUID: String] = [:]
    @State private var sending = false
    @State private var showRules = false

    private var frames: [Shot] { roll.droppable }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Pick what the wall sees. Everything else stays yours.")
                        .font(.displayItal(15))
                        .foregroundStyle(Ink.mist)

                    ForEach(frames) { shot in
                        DropPick(shot: shot,
                                 selected: picked.contains(shot.id),
                                 caption: Binding(
                                    get: { captions[shot.id] ?? "" },
                                    set: { captions[shot.id] = $0 }))
                        { toggle(shot) }
                    }

                    if frames.isEmpty {
                        Text("Nothing developed to drop yet.")
                            .font(.body_(14))
                            .foregroundStyle(Ink.mist)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                    }
                }
                .padding(18)
                .padding(.bottom, 90)
            }
            .background(Ink.night)
            .safeAreaInset(edge: .bottom) {
                Button {
                    if wall.rulesAccepted { send() } else { showRules = true }
                } label: {
                            Text(sending ? "DROPPING…" : picked.isEmpty ? "PICK A FRAME" : "ADD \(picked.count) TO THE WALL")
                        .font(.mono(11, .bold)).tracking(2.2)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Ink.gold, in: Capsule())
                        .padding(.horizontal, 18)
                        .padding(.bottom, 10)
                }
                .buttonStyle(.plain)
                .disabled(picked.isEmpty || sending)
                .opacity(picked.isEmpty ? 0.4 : 1)
                .background(Ink.night)
            }
            .navigationTitle("TO THE WALL")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("NOT NOW") { dismiss() }
                        .font(.mono(10, .bold)).tint(Ink.gold)
                }
            }
            .toolbarBackground(Ink.night, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .sheet(isPresented: $showRules) {
                RulesSheet { wall.rulesAccepted = true; showRules = false; send() }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func toggle(_ shot: Shot) {
        if picked.contains(shot.id) { picked.remove(shot.id) } else { picked.insert(shot.id) }
    }

    private func send() {
        guard !picked.isEmpty else { return }
        sending = true
        let chosen = frames.filter { picked.contains($0.id) }
        Task {
            await wall.drop(chosen, captions: captions, from: roll)
            sending = false
            dismiss()
        }
    }
}

private struct DropPick: View {
    let shot: Shot
    let selected: Bool
    @Binding var caption: String
    let onTap: () -> Void

    @ObservedObject private var roll = RollStore.shared
    @State private var ui: UIImage?

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onTap) {
                ZStack(alignment: .topTrailing) {
                    if let ui {
                        Image(uiImage: ui)
                            .resizable().scaledToFill()
                            .frame(height: 260)
                            .clipped()
                    } else {
                        Ink.charcoal.frame(height: 260)
                    }
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22))
                        .foregroundStyle(selected ? Ink.gold : .white.opacity(0.8))
                        .shadow(radius: 4)
                        .padding(12)
                }
                .frame(height: 260)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if selected {
                TextField("say something (optional)", text: $caption)
                    .font(.body_(14))
                    .foregroundStyle(.white)
                    .tint(Ink.gold)
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .background(Ink.charcoal)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18)
            .strokeBorder(selected ? Ink.gold : .white.opacity(0.1), lineWidth: selected ? 1.5 : 0.8))
        .task(id: shot.id) { if ui == nil { ui = roll.image(for: shot) } }
    }
}

/// Agreed to once, before the first frame leaves the phone. A shared wall needs
/// a line everybody has read, and a way to answer when somebody crosses it.
struct RulesSheet: View {
    let onAgree: () -> Void
    @Environment(\.dismiss) private var dismiss

    private let rules = [
        "Shoot your own frames. Nobody else's work goes up as yours.",
        "No nudity, hate, harassment, or anything unsafe for a public wall.",
        "Ask before reposting somebody else's frame outside the app.",
        "Report anything that breaks this. Blocking is instant, and reports get read.",
    ]

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    Text("FOUR RULES")
                        .font(.display(34))
                        .foregroundStyle(Ink.gold)

                    ForEach(Array(rules.enumerated()), id: \.offset) { i, rule in
                        HStack(alignment: .top, spacing: 12) {
                            Text(String(format: "%02d", i + 1))
                                .font(.mono(11, .bold))
                                .foregroundStyle(Ink.goldDeep)
                            Text(rule)
                                .font(.body_(15))
                                .foregroundStyle(.white.opacity(0.9))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Text("Break them and the frame comes down and the account comes off the wall. This is a public room, and it stays good because everybody protects it.")
                        .font(.body_(13))
                        .foregroundStyle(Ink.mist)
                        .padding(.top, 4)

                    Button(action: onAgree) {
                        Text("I'M GOOD WITH THAT")
                            .font(.mono(11, .bold)).tracking(2.2)
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Ink.gold, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 10)
                }
                .padding(22)
            }
            .background(Ink.night)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("BACK") { dismiss() }.font(.mono(10, .bold)).tint(Ink.gold)
                }
            }
            .toolbarBackground(Ink.night, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }
}
