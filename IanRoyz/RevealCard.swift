import SwiftUI
import UIKit

/// A shareable receipt of a week. The app is the archive; this card is the
/// artifact that can leave it without looking like a generic screenshot.
@MainActor
enum RevealCard {
    static func make(for shots: [Shot], store: RollStore) -> URL? {
        let images = shots.compactMap { store.image(for: $0) }.prefix(4)
        guard !images.isEmpty else { return nil }

        let renderer = ImageRenderer(content: ContactSheet(images: Array(images)))
        renderer.scale = 3
        guard let data = renderer.uiImage?.jpegData(compressionQuality: 0.92) else { return nil }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ianroyz-week-\(UUID().uuidString).jpg")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    private struct ContactSheet: View {
        let images: [UIImage]

        var body: some View {
            ZStack {
                LinearGradient(colors: [Ink.skyDeep, Ink.night], startPoint: .topLeading, endPoint: .bottomTrailing)
                VStack(alignment: .leading, spacing: 22) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("IAN ROYZ")
                                .font(.system(size: 40, weight: .bold, design: .serif))
                                .foregroundStyle(Ink.gold)
                            Text("THE ROLL · WEEK IN FRAMES")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .tracking(2.4)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        Spacer()
                        Text("06:40")
                            .font(.system(size: 15, weight: .bold, design: .monospaced))
                            .foregroundStyle(Ink.gold)
                    }

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        ForEach(Array(images.enumerated()), id: \.offset) { _, image in
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(height: 280)
                                .clipped()
                        }
                    }

                    HStack {
                        Text(Date.now, format: .dateTime.month(.abbreviated).day().year())
                        Spacer()
                        Text("SHOT ON IAN ROYZ")
                    }
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(1.6)
                    .foregroundStyle(.white.opacity(0.55))
                }
                .padding(34)
            }
            .frame(width: 1080, height: 1350)
        }
    }
}
