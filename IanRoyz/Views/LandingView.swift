import SwiftUI

// The door: BORED plays full-bleed, gold serif over it, tap to enter.
struct LandingView: View {
    let onEnter: () -> Void
    @State private var pulse = false
    @State private var showType = false

    var body: some View {
        ZStack {
            LoopingVideoLayer(resource: "landing_les")
                .ignoresSafeArea()

            // cinematic wash
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.55), location: 0),
                    .init(color: .black.opacity(0.05), location: 0.35),
                    .init(color: .black.opacity(0.1), location: 0.6),
                    .init(color: .black.opacity(0.75), location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            Grain(opacity: 0.05).ignoresSafeArea()

            VStack {
                VStack(spacing: 14) {
                    Kicker(text: "·• A Personal Archive •·", color: Ink.gold.opacity(0.9))
                        .opacity(showType ? 1 : 0)
                        .offset(y: showType ? 0 : 10)

                    Text("IAN\nROYZ")
                        .font(.display(92))
                        .foregroundStyle(Ink.gold)
                        .multilineTextAlignment(.center)
                        .lineSpacing(-18)
                        .shadow(color: .black.opacity(0.4), radius: 24, y: 8)
                        .opacity(showType ? 1 : 0)
                        .scaleEffect(showType ? 1 : 1.06)

                    HStack(spacing: 24) {
                        Kicker(text: "Head in the clouds", size: 9)
                        Kicker(text: "Dreaming out loud", size: 9)
                    }
                    .opacity(showType ? 1 : 0)
                }
                .padding(.top, 110)

                Spacer()

                VStack(spacing: 18) {
                    Text("UNAPOLOGETIC CREATIVE")
                        .font(.displayItal(15))
                        .foregroundStyle(Ink.gold)
                        .tracking(2)

                    Button(action: onEnter) {
                        HStack(spacing: 10) {
                            Text("TAP TO ENTER")
                                .font(.mono(11, .bold))
                                .tracking(3)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundStyle(.black)
                        .padding(.horizontal, 26)
                        .padding(.vertical, 14)
                        .background(Ink.gold, in: Capsule())
                        .shadow(color: Ink.gold.opacity(pulse ? 0.55 : 0.15), radius: pulse ? 26 : 10)
                        .scaleEffect(pulse ? 1.03 : 1)
                    }

                    Kicker(text: "LES · dir. Ian Royes · 0:42", color: .white.opacity(0.4), size: 8)
                }
                .padding(.bottom, 54)
                .opacity(showType ? 1 : 0)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onEnter)
        .onAppear {
            withAnimation(.easeOut(duration: 1.4).delay(0.4)) { showType = true }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true).delay(1.2)) { pulse = true }
        }
    }
}
