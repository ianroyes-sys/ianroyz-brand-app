import SwiftUI

// MARK: - Palette · "DAYDREAM"
// Sky + butter gold, ink for the film rooms, paper for the notes.
enum Ink {
    static let sky       = Color(red: 0.32, green: 0.58, blue: 0.85)   // cerulean
    static let skyDeep   = Color(red: 0.18, green: 0.42, blue: 0.72)
    static let skyPale   = Color(red: 0.62, green: 0.78, blue: 0.94)
    static let gold      = Color(red: 0.93, green: 0.87, blue: 0.55)   // butter gold
    static let goldDeep  = Color(red: 0.82, green: 0.72, blue: 0.34)
    static let night     = Color(red: 0.05, green: 0.06, blue: 0.08)   // ink
    static let charcoal  = Color(red: 0.09, green: 0.10, blue: 0.13)
    static let paper     = Color(red: 0.96, green: 0.94, blue: 0.88)   // cream
    static let paperInk  = Color(red: 0.16, green: 0.14, blue: 0.11)
    static let cloud     = Color.white
    static let mist      = Color.white.opacity(0.65)
}

// MARK: - Type
extension Font {
    static func display(_ size: CGFloat) -> Font { .system(size: size, weight: .bold, design: .serif) }
    static func displayItal(_ size: CGFloat) -> Font { .system(size: size, weight: .semibold, design: .serif).italic() }
    static func body_(_ size: CGFloat) -> Font { .system(size: size, weight: .regular, design: .serif) }
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font { .system(size: size, weight: weight, design: .monospaced) }
}

// Small uppercase tracked label, editorial style.
struct Kicker: View {
    let text: String
    var color: Color = Ink.mist
    var size: CGFloat = 10
    var body: some View {
        Text(text.uppercased())
            .font(.mono(size, .semibold))
            .tracking(3.2)
            .foregroundStyle(color)
    }
}

// MARK: - Bundle media helpers

/// Decoded-image cache.
///
/// `bundleImage` used to be called straight from `Photo`'s body, which sits inside
/// a GeometryReader — so every layout pass re-read and re-decoded the JPEG from
/// disk. Scrolling STILLS (27 frames) meant decoding 27 photos per frame. NSCache
/// keeps decoded images around and evicts them itself under memory pressure, so
/// the big rooms scroll instead of stutter.
private let imageCache: NSCache<NSString, UIImage> = {
    let c = NSCache<NSString, UIImage>()
    c.countLimit = 120
    return c
}()

/// HEIC first, then JPEG. The bundled photography is all HEIC (roughly a third
/// smaller than the same frame as JPEG at the same quality); the JPEG fallback
/// is for anything dropped in later without being converted.
func bundleImage(_ name: String) -> UIImage? {
    if let hit = imageCache.object(forKey: name as NSString) { return hit }
    let url = Bundle.main.url(forResource: name, withExtension: "heic")
        ?? Bundle.main.url(forResource: name, withExtension: "jpg")
    guard let url, let ui = UIImage(contentsOfFile: url.path) else { return nil }
    imageCache.setObject(ui, forKey: name as NSString)
    return ui
}

/// scaledToFill inside a fixed frame — always pair with .clipped() (see FillImage gotcha).
struct Photo: View {
    let name: String
    /// Resolved once per name rather than on every layout pass.
    @State private var ui: UIImage?

    var body: some View {
        GeometryReader { geo in
            if let ui {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            } else {
                Ink.charcoal
            }
        }
        // `.clipped()` clips pixels, NOT taps: a scaledToFill image overflows its
        // frame and keeps swallowing touches outside it, which lands hardest on
        // iPad where the frames are widest. This is the 2.1a rejection that took
        // WHO Worship down. Every Photo now hit-tests to its own frame and no
        // further.
        .contentShape(Rectangle())
        .task(id: name) {
            guard ui == nil else { return }
            ui = bundleImage(name)
        }
    }
}

// MARK: - Grain overlay (static noise, drawn once per size)
struct Grain: View {
    var opacity: Double = 0.06
    var body: some View {
        Canvas { ctx, size in
            var rng = SeededRandom(seed: 7)
            for _ in 0..<1400 {
                let x = rng.next() * size.width
                let y = rng.next() * size.height
                let w = 0.7 + rng.next() * 0.9
                ctx.fill(Path(CGRect(x: x, y: y, width: w, height: w)),
                         with: .color(.white.opacity(0.5 + rng.next() * 0.5)))
            }
        }
        .opacity(opacity)
        .allowsHitTesting(false)
    }
}

struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 6364136223846793005 &+ 1442695040888963407 }
    mutating func next() -> CGFloat {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat((state >> 33) & 0xFFFFFF) / CGFloat(0xFFFFFF)
    }
}

// MARK: - Drifting clouds
struct DriftingClouds: View {
    @State private var drift = false
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack {
                cloudBlob(width: w * 0.9, height: 90, blur: 26, opacity: 0.85)
                    .offset(x: drift ? w * 0.35 : -w * 0.45, y: geo.size.height * 0.16)
                    .animation(.linear(duration: 56).repeatForever(autoreverses: true), value: drift)
                cloudBlob(width: w * 0.65, height: 60, blur: 22, opacity: 0.6)
                    .offset(x: drift ? -w * 0.4 : w * 0.4, y: geo.size.height * 0.42)
                    .animation(.linear(duration: 74).repeatForever(autoreverses: true), value: drift)
                cloudBlob(width: w * 0.5, height: 44, blur: 18, opacity: 0.45)
                    .offset(x: drift ? w * 0.3 : -w * 0.35, y: geo.size.height * 0.68)
                    .animation(.linear(duration: 88).repeatForever(autoreverses: true), value: drift)
            }
        }
        .onAppear { drift = true }
        .allowsHitTesting(false)
    }

    private func cloudBlob(width: CGFloat, height: CGFloat, blur: CGFloat, opacity: Double) -> some View {
        ZStack {
            Ellipse().frame(width: width, height: height)
            Ellipse().frame(width: width * 0.55, height: height * 1.35).offset(x: -width * 0.18, y: -height * 0.3)
            Ellipse().frame(width: width * 0.4, height: height * 1.1).offset(x: width * 0.22, y: -height * 0.2)
        }
        .foregroundStyle(Ink.cloud)
        .blur(radius: blur)
        .opacity(opacity)
    }
}

// MARK: - Marquee ticker
struct Marquee: View {
    let items: [String]
    var font: Font = .mono(11, .semibold)
    var color: Color = Ink.gold
    var separator: String = "  ✕  "
    @State private var animate = false

    var body: some View {
        let line = items.map { $0.uppercased() }.joined(separator: separator) + separator
        GeometryReader { geo in
            HStack(spacing: 0) {
                Text(line).fixedSize()
                Text(line).fixedSize()
            }
            .font(font)
            .tracking(2)
            .foregroundStyle(color)
            .offset(x: animate ? -textWidth(line) : 0)
            .animation(.linear(duration: Double(line.count) * 0.22).repeatForever(autoreverses: false), value: animate)
            .frame(height: geo.size.height, alignment: .center)
        }
        .frame(height: 30)
        .clipped()
        .onAppear { animate = true }
        .allowsHitTesting(false)
    }

    private func textWidth(_ s: String) -> CGFloat {
        let attr = [NSAttributedString.Key.font: UIFont.monospacedSystemFont(ofSize: 11, weight: .semibold)]
        return ceil((s as NSString).size(withAttributes: attr).width) + CGFloat(s.count) * 2
    }
}

// MARK: - Runtime chip
struct RuntimeChip: View {
    let seconds: Int
    var body: some View {
        Text(runtimeString(seconds))
            .font(.mono(10, .bold))
            .tracking(1)
            .foregroundStyle(.black)
            .padding(.horizontal, 7)
            .padding(.vertical, 3.5)
            .background(Ink.gold, in: Capsule())
    }
}

func runtimeString(_ seconds: Int) -> String {
    String(format: "%d:%02d", seconds / 60, seconds % 60)
}

// MARK: - Section shell (dark rooms)
struct RoomHeader: View {
    let kicker: String
    let title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Kicker(text: kicker, color: Ink.goldDeep)
            Text(title)
                .font(.display(52))
                .foregroundStyle(Ink.gold)
                .lineSpacing(-6)
                .minimumScaleFactor(0.6)
                .lineLimit(2)
            if let subtitle {
                Text(subtitle)
                    .font(.displayItal(16))
                    .foregroundStyle(Ink.mist)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// Reveal-on-scroll wrapper
extension View {
    func reveal() -> some View {
        scrollTransition(.animated(.spring(duration: 0.6))) { content, phase in
            content
                .opacity(phase.isIdentity ? 1 : 0)
                .offset(y: phase.isIdentity ? 0 : 34)
                .scaleEffect(phase.isIdentity ? 1 : 0.97)
        }
    }
}

// Custom back button for dark rooms
struct RoomBack: ViewModifier {
    @Environment(\.dismiss) private var dismiss
    var tint: Color = Ink.gold
    func body(content: Content) -> some View {
        content
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.left")
                            Text("BACK").font(.mono(10, .bold)).tracking(2)
                        }
                        .foregroundStyle(tint)
                    }
                }
            }
    }
}
extension View { func roomBack(_ tint: Color = Ink.gold) -> some View { modifier(RoomBack(tint: tint)) } }
