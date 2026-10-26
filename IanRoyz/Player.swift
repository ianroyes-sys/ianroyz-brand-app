import SwiftUI
import AVKit

// MARK: - Looping, muted, fill-screen video layer (landing page)
struct LoopingVideoLayer: UIViewRepresentable {
    let resource: String
    /// Ambient loops are decorative. Home keeps one running behind the module
    /// stack under an 82%-opaque black overlay — that's a decoder burning
    /// battery to render something nobody can see once it scrolls away.
    var active: Bool = true

    func makeUIView(context: Context) -> LoopingPlayerUIView {
        LoopingPlayerUIView(resource: resource)
    }
    func updateUIView(_ uiView: LoopingPlayerUIView, context: Context) {
        uiView.setActive(active)
    }
}

final class LoopingPlayerUIView: UIView {
    private var looper: AVPlayerLooper?
    private let playerLayer = AVPlayerLayer()

    init(resource: String) {
        super.init(frame: .zero)
        guard let url = Bundle.main.url(forResource: resource, withExtension: "mp4") else { return }
        let item = AVPlayerItem(url: url)
        let queue = AVQueuePlayer()
        queue.isMuted = true
        looper = AVPlayerLooper(player: queue, templateItem: item)
        playerLayer.player = queue
        playerLayer.videoGravity = .resizeAspectFill
        layer.addSublayer(playerLayer)
        queue.play()

        NotificationCenter.default.addObserver(
            self, selector: #selector(resume),
            name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    private var wantsPlayback = true

    /// Pause when the loop scrolls out of sight; resume when it comes back.
    func setActive(_ active: Bool) {
        guard active != wantsPlayback else { return }
        wantsPlayback = active
        active ? playerLayer.player?.play() : playerLayer.player?.pause()
    }

    @objc private func resume() {
        guard wantsPlayback else { return }
        playerLayer.player?.play()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }
}

// MARK: - Fullscreen film player
struct FilmPlayer: View {
    let resource: String
    let title: String
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            }
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Kicker(text: "Now Screening", color: Ink.gold)
                    Text(title)
                        .font(.display(20))
                        .foregroundStyle(.white)
                }
                Spacer()
                // A film nobody can pass on is a film nobody else sees.
                if let url = Bundle.main.url(forResource: resource, withExtension: "mp4") {
                    ShareLink(item: url, preview: SharePreview(title)) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                }
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(.ultraThinMaterial, in: Circle())
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        // The films are cinematic and wide; the app is portrait-locked everywhere
        // else, so the player is the one screen allowed to turn. Without this the
        // work plays in a letterboxed strip down the middle of the phone.
        .supportedInterfaceOrientations(.allButUpsideDown)
        .onAppear {
            guard let url = Bundle.main.url(forResource: resource, withExtension: "mp4") else { return }
            let p = AVPlayer(url: url)
            player = p
            p.play()
        }
        .onDisappear {
            player?.pause()
            player = nil          // release the decoder rather than leaving it parked
        }
    }
}

// Convenience modifier to present a film fullscreen
struct FilmPresenter: ViewModifier {
    @Binding var film: Film?
    func body(content: Content) -> some View {
        content.fullScreenCover(item: $film) { f in
            FilmPlayer(resource: f.id, title: f.title)
        }
    }
}
extension View {
    func filmPlayer(_ film: Binding<Film?>) -> some View { modifier(FilmPresenter(film: film)) }
}
