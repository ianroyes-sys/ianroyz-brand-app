// HEVC re-encoder. Keeps resolution, frame rate and duration exactly; only the
// codec and bitrate change. Usage: reencode <in.mp4> <out.mp4> [videoKbps] [audioKbps]
import AVFoundation
import Foundation
import VideoToolbox

let args = CommandLine.arguments
guard args.count >= 3 else { fputs("usage: reencode in out [vkbps] [akbps]\n", stderr); exit(2) }
let inURL = URL(fileURLWithPath: args[1])
let outURL = URL(fileURLWithPath: args[2])
let overrideV = args.count > 3 ? Int(args[3]) : nil
let audioKbps = args.count > 4 ? (Int(args[4]) ?? 96) : 96

func fail(_ m: String) -> Never { fputs("ERROR \(inURL.lastPathComponent): \(m)\n", stderr); exit(1) }

let sem = DispatchSemaphore(value: 0)

Task {
    let asset = AVURLAsset(url: inURL)
    guard let vTrack = (try? await asset.loadTracks(withMediaType: .video))?.first else { fail("no video track") }
    let aTrack = (try? await asset.loadTracks(withMediaType: .audio))?.first

    let size = try await vTrack.load(.naturalSize)
    let transform = try await vTrack.load(.preferredTransform)
    let fps = try await vTrack.load(.nominalFrameRate)
    let h = min(abs(size.width), abs(size.height))

    // Bitrate ladder: HEVC needs roughly half of H.264 for the same look. Base is
    // tuned for 24fps; high-frame-rate material gets a proportional bump.
    let base: Double = h <= 560 ? 1_000_000 : 1_600_000
    let motionFactor: Double = fps > 45 ? 1.35 : (fps > 27 ? 1.12 : 1.0)
    let vBitrate = overrideV.map { $0 * 1000 } ?? Int(base * motionFactor)

    try? FileManager.default.removeItem(at: outURL)
    guard let writer = try? AVAssetWriter(outputURL: outURL, fileType: .mp4) else { fail("writer") }
    guard let reader = try? AVAssetReader(asset: asset) else { fail("reader") }

    let vOut = AVAssetReaderTrackOutput(track: vTrack, outputSettings: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
    ])
    vOut.alwaysCopiesSampleData = false
    reader.add(vOut)

    let vIn = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.hevc,
        AVVideoWidthKey: Int(abs(size.width)),
        AVVideoHeightKey: Int(abs(size.height)),
        AVVideoCompressionPropertiesKey: [
            AVVideoAverageBitRateKey: vBitrate,
            AVVideoProfileLevelKey: kVTProfileLevel_HEVC_Main_AutoLevel,
            AVVideoMaxKeyFrameIntervalDurationKey: 2.0,
            AVVideoExpectedSourceFrameRateKey: Int(fps.rounded()),
            AVVideoAllowFrameReorderingKey: true,
        ] as [String: Any],
    ])
    vIn.expectsMediaDataInRealTime = false
    vIn.transform = transform
    writer.add(vIn)

    var aOut: AVAssetReaderTrackOutput?
    var aIn: AVAssetWriterInput?
    if let aTrack {
        let o = AVAssetReaderTrackOutput(track: aTrack, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ])
        o.alwaysCopiesSampleData = false
        reader.add(o)
        aOut = o

        let desc = try await aTrack.load(.formatDescriptions)
        var channels = 2
        var rate = 44_100.0
        if let d = desc.first, let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(d)?.pointee {
            channels = Int(asbd.mChannelsPerFrame)
            rate = asbd.mSampleRate
        }
        let i = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: min(channels, 2),
            AVSampleRateKey: rate,
            AVEncoderBitRateKey: audioKbps * 1000,
        ])
        i.expectsMediaDataInRealTime = false
        writer.add(i)
        aIn = i
    }

    writer.shouldOptimizeForNetworkUse = true
    guard reader.startReading() else { fail("startReading \(reader.error?.localizedDescription ?? "")") }
    guard writer.startWriting() else { fail("startWriting \(writer.error?.localizedDescription ?? "")") }
    writer.startSession(atSourceTime: .zero)

    let group = DispatchGroup()
    let vQueue = DispatchQueue(label: "v")
    group.enter()
    vIn.requestMediaDataWhenReady(on: vQueue) {
        while vIn.isReadyForMoreMediaData {
            if let sb = vOut.copyNextSampleBuffer() {
                if !vIn.append(sb) { break }
            } else {
                vIn.markAsFinished()
                group.leave()
                return
            }
        }
    }

    if let aIn, let aOut {
        let aQueue = DispatchQueue(label: "a")
        group.enter()
        aIn.requestMediaDataWhenReady(on: aQueue) {
            while aIn.isReadyForMoreMediaData {
                if let sb = aOut.copyNextSampleBuffer() {
                    if !aIn.append(sb) { break }
                } else {
                    aIn.markAsFinished()
                    group.leave()
                    return
                }
            }
        }
    }

    // Not .main — main is parked on the semaphore below, so a notify there deadlocks.
    group.notify(queue: DispatchQueue.global()) {
        writer.finishWriting {
            if writer.status != .completed {
                fputs("ERROR \(inURL.lastPathComponent): \(writer.error?.localizedDescription ?? "unknown")\n", stderr)
                exit(1)
            }
            if reader.status == .failed {
                fputs("ERROR read \(inURL.lastPathComponent): \(reader.error?.localizedDescription ?? "")\n", stderr)
                exit(1)
            }
            let a = (try? FileManager.default.attributesOfItem(atPath: inURL.path)[.size] as? Int) ?? 0
            let b = (try? FileManager.default.attributesOfItem(atPath: outURL.path)[.size] as? Int) ?? 0
            let mbA = Double(a ?? 0) / 1_048_576, mbB = Double(b ?? 0) / 1_048_576
            print(String(format: "%@ %.1fMB -> %.1fMB (%.0f%% saved, %d kbps)",
                         inURL.lastPathComponent, mbA, mbB,
                         mbA > 0 ? (1 - mbB / mbA) * 100 : 0, vBitrate / 1000))
            sem.signal()
        }
    }
}
sem.wait()
