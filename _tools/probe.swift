import AVFoundation
import Foundation

let paths = Array(CommandLine.arguments.dropFirst())
let sem = DispatchSemaphore(value: 0)

Task {
    for p in paths {
        let url = URL(fileURLWithPath: p)
        let asset = AVURLAsset(url: url)
        guard let dur = try? await asset.load(.duration) else { continue }
        let secs = CMTimeGetSeconds(dur)
        let tracks = (try? await asset.loadTracks(withMediaType: .video)) ?? []
        let atracks = (try? await asset.loadTracks(withMediaType: .audio)) ?? []
        var line = URL(fileURLWithPath: p).lastPathComponent
        line += String(format: " | %.1fs", secs)
        if let v = tracks.first {
            let size = (try? await v.load(.naturalSize)) ?? .zero
            let t = (try? await v.load(.preferredTransform)) ?? .identity
            let disp = size.applying(t)
            let fps = (try? await v.load(.nominalFrameRate)) ?? 0
            let br = (try? await v.load(.estimatedDataRate)) ?? 0
            let fd = (try? await v.load(.formatDescriptions)) ?? []
            var codec = "?"
            if let f = fd.first {
                let c = CMFormatDescriptionGetMediaSubType(f as! CMFormatDescription)
                codec = String(format: "%c%c%c%c", (c >> 24) & 255, (c >> 16) & 255, (c >> 8) & 255, c & 255)
            }
            line += String(format: " | %dx%d (disp %dx%d) | %.2ffps | %.2f Mbps | %@",
                           Int(size.width), Int(size.height),
                           Int(abs(disp.width)), Int(abs(disp.height)), fps, br / 1_000_000, codec)
        }
        if let a = atracks.first {
            let br = (try? await a.load(.estimatedDataRate)) ?? 0
            line += String(format: " | audio %.0f kbps", br / 1000)
        } else {
            line += " | no audio"
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: p)[.size] as? Int) ?? 0
        line += String(format: " | %.1f MB", Double(size ?? 0) / 1_048_576)
        print(line)
    }
    sem.signal()
}
sem.wait()
