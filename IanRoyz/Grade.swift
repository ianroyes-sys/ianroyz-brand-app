import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

// MARK: - The grades
//
// The look is the brand, so it lives in code rather than in a .cube file — every
// grade here is a hand-tuned Core Image chain named after the work it came from.
// One `CIContext` is shared for the whole app: creating one per frame is the
// classic way to make a live camera preview crawl.

enum GradeEngine {
    /// Shared, GPU-backed. Built once — a per-frame CIContext tanks the preview.
    static let context: CIContext = {
        CIContext(options: [.useSoftwareRenderer: false, .cacheIntermediates: false])
    }()
}

struct Grade: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    /// Shown under the name on the grade picker — what the look is *for*.
    let note: String

    // Chain parameters. Kept as plain numbers so a grade is data, not a subclass.
    let temperature: CGFloat      // target neutral, 6500 = unchanged
    let tint: CGFloat
    let saturation: CGFloat
    let contrast: CGFloat
    let brightness: CGFloat
    let shadowTint: CIColor       // lifted into the blacks
    let shadowAmount: CGFloat
    let highlightTint: CIColor
    let highlightAmount: CGFloat
    let grain: CGFloat            // 0…1
    let vignette: CGFloat

    static func == (a: Grade, b: Grade) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

extension Grade {
    /// DAYDREAM — the app's own palette: cerulean sky, butter gold, soft lift.
    static let daydream = Grade(
        id: "daydream", name: "DAYDREAM", note: "sky + butter gold",
        temperature: 7000, tint: 4, saturation: 1.12, contrast: 1.04, brightness: 0.02,
        shadowTint: CIColor(red: 0.32, green: 0.58, blue: 0.85), shadowAmount: 0.16,
        highlightTint: CIColor(red: 0.93, green: 0.87, blue: 0.55), highlightAmount: 0.20,
        grain: 0.22, vignette: 0.35)

    /// CAN'T KILL THE SOUTH — gold light, loud grass, chrome.
    static let south = Grade(
        id: "south", name: "CAN'T KILL THE SOUTH", note: "gold light, loud grass",
        temperature: 7600, tint: 10, saturation: 1.26, contrast: 1.10, brightness: 0.01,
        shadowTint: CIColor(red: 0.20, green: 0.16, blue: 0.10), shadowAmount: 0.20,
        highlightTint: CIColor(red: 1.0, green: 0.82, blue: 0.42), highlightAmount: 0.26,
        grain: 0.28, vignette: 0.42)

    /// GOLDEN HOUR — the forty-minute window. Warmest of the set.
    static let golden = Grade(
        id: "golden", name: "GOLDEN HOUR", note: "the forty minutes",
        temperature: 8200, tint: 6, saturation: 1.18, contrast: 1.02, brightness: 0.04,
        shadowTint: CIColor(red: 0.35, green: 0.22, blue: 0.14), shadowAmount: 0.22,
        highlightTint: CIColor(red: 1.0, green: 0.76, blue: 0.36), highlightAmount: 0.34,
        grain: 0.20, vignette: 0.30)

    /// LOST FILES — recovered-from-a-drive fade. Low contrast, milky blacks.
    static let lost = Grade(
        id: "lost", name: "LOST FILES", note: "recovered, not restored",
        temperature: 6200, tint: -6, saturation: 0.82, contrast: 0.92, brightness: 0.05,
        shadowTint: CIColor(red: 0.42, green: 0.40, blue: 0.36), shadowAmount: 0.30,
        highlightTint: CIColor(red: 0.90, green: 0.88, blue: 0.80), highlightAmount: 0.16,
        grain: 0.42, vignette: 0.22)

    /// MIDNIGHT — the ink rooms. Chiaroscuro, cold, heavy falloff.
    static let midnight = Grade(
        id: "midnight", name: "MIDNIGHT", note: "chiaroscuro",
        temperature: 5400, tint: -10, saturation: 0.88, contrast: 1.22, brightness: -0.05,
        shadowTint: CIColor(red: 0.06, green: 0.09, blue: 0.16), shadowAmount: 0.34,
        highlightTint: CIColor(red: 0.78, green: 0.84, blue: 0.95), highlightAmount: 0.14,
        grain: 0.26, vignette: 0.55)

    static let all: [Grade] = [.daydream, .south, .golden, .lost, .midnight]

    static func named(_ id: String) -> Grade { all.first { $0.id == id } ?? .daydream }
}

// MARK: - Application

extension Grade {
    /// Full-quality apply, for developing a shot.
    func apply(to input: CIImage) -> CIImage { build(input, fast: false) }

    /// Cheaper chain for the live preview — grain and vignette are the two
    /// generators that cost the most per frame and read the least at preview size.
    func applyFast(to input: CIImage) -> CIImage { build(input, fast: true) }

    private func build(_ input: CIImage, fast: Bool) -> CIImage {
        var img = input

        // 1 — white balance toward the grade's neutral
        let temp = CIFilter.temperatureAndTint()
        temp.inputImage = img
        temp.neutral = CIVector(x: temperature, y: tint)
        temp.targetNeutral = CIVector(x: 6500, y: 0)
        img = temp.outputImage ?? img

        // 2 — tone
        let color = CIFilter.colorControls()
        color.inputImage = img
        color.saturation = Float(saturation)
        color.contrast = Float(contrast)
        color.brightness = Float(brightness)
        img = color.outputImage ?? img

        // 3 — split tone. Two multiply/screen passes, cheap and the whole
        //     reason these grades read as a look rather than a slider preset.
        img = tint(img, color: shadowTint, amount: shadowAmount, highlights: false)
        img = tint(img, color: highlightTint, amount: highlightAmount, highlights: true)

        guard !fast else { return img }

        // 4 — vignette
        if vignette > 0 {
            let v = CIFilter.vignette()
            v.inputImage = img
            v.intensity = Float(vignette)
            v.radius = 1.6
            img = v.outputImage ?? img
        }

        // 5 — grain, clamped to the source extent so the noise generator's
        //     infinite extent doesn't blow the render out to infinity.
        if grain > 0 {
            let noise = CIFilter.randomGenerator()
            if let n = noise.outputImage?.cropped(to: img.extent) {
                let mono = CIFilter.colorControls()
                mono.inputImage = n
                mono.saturation = 0
                mono.contrast = 1
                mono.brightness = 0
                if let m = mono.outputImage {
                    let blend = CIFilter.sourceOverCompositing()
                    blend.inputImage = m.applyingFilter("CIColorMatrix", parameters: [
                        "inputAVector": CIVector(x: 0, y: 0, z: 0, w: grain * 0.16)
                    ])
                    blend.backgroundImage = img
                    img = blend.outputImage ?? img
                }
            }
        }

        return img
    }

    /// A real split tone: the colour is blended through a **luminance mask**, so
    /// shadow tint lands in the shadows and highlight tint in the highlights.
    ///
    /// The first version screened/multiplied a flat colour over the entire frame,
    /// which lifts the blacks everywhere and reads as a milky wash rather than a
    /// grade — the exact thing that separates a look from a filter preset.
    private func tint(_ img: CIImage, color: CIColor, amount: CGFloat, highlights: Bool) -> CIImage {
        guard amount > 0 else { return img }

        // Rec.709 luminance, as a greyscale image.
        let luma = img.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0),
            "inputGVector": CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0),
            "inputBVector": CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
        ])

        // Highlights use luminance directly; shadows use its inverse. Scaling the
        // mask by `amount` is what keeps the tint from taking over the frame.
        var mask = highlights ? luma : luma.applyingFilter("CIColorInvert")
        mask = mask.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: amount, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: amount, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: amount, w: 0),
        ])

        let solid = CIImage(color: color).cropped(to: img.extent)
        let blend = highlights ? CIFilter.screenBlendMode() : CIFilter.multiplyBlendMode()
        blend.inputImage = solid
        blend.backgroundImage = img
        guard let toned = blend.outputImage else { return img }

        let masked = CIFilter.blendWithMask()
        masked.inputImage = toned
        masked.backgroundImage = img
        masked.maskImage = mask
        return masked.outputImage?.cropped(to: img.extent) ?? img
    }

    /// Render to a UIImage. Returns nil rather than a blank frame on failure.
    func render(_ input: CIImage) -> UIImage? {
        let out = apply(to: input)
        guard let cg = GradeEngine.context.createCGImage(out, from: out.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
