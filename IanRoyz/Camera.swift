import SwiftUI
@preconcurrency import AVFoundation
import CoreImage
import PhotosUI

// MARK: - The camera
//
// Live preview runs through the selected grade, so you are looking through the
// lens the work was made with rather than picking a filter afterwards.
//
// The preview is a CIImage → CGImage render rather than AVCaptureVideoPreviewLayer,
// because the whole point is that the grade is visible while you shoot; a preview
// layer would show the ungraded feed.

@MainActor
final class CameraController: NSObject, ObservableObject {
    @Published var preview: CGImage?
    @Published var authorized = false
    @Published var running = false
    /// Simulator has no camera — the room falls back to a library import.
    @Published var unavailable = false

    var grade: Grade = .daydream

    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "com.ianroyz.camera", qos: .userInitiated)
    private var configured = false

    /// Set by the shutter; the next frame is captured full-quality and handed back.
    private var pendingCapture: ((UIImage) -> Void)?

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            authorized = true
            configureAndRun()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { ok in
                Task { @MainActor in
                    self.authorized = ok
                    if ok { self.configureAndRun() }
                }
            }
        default:
            authorized = false
        }
    }

    func stop() {
        queue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
        running = false
    }

    private func configureAndRun() {
        guard !configured else {
            queue.async { [session] in if !session.isRunning { session.startRunning() } }
            running = true
            return
        }

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else {
            unavailable = true
            return
        }

        session.beginConfiguration()
        session.sessionPreset = .photo
        if session.canAddInput(input) { session.addInput(input) }
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(output) { session.addOutput(output) }
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            photoOutput.maxPhotoQualityPrioritization = .quality
        }
        session.commitConfiguration()
        configured = true

        queue.async { [session] in session.startRunning() }
        running = true
    }

    /// A real still capture carries substantially more detail than a frame from
    /// the live preview. The preview stays fast; only the sealed frame pays for
    /// the full-quality capture and grade.
    func capture(_ completion: @escaping (UIImage) -> Void) {
        pendingCapture = completion
        let settings = AVCapturePhotoSettings()
        settings.photoQualityPrioritization = .quality
        photoOutput.capturePhoto(with: settings, delegate: self)
    }
}

extension CameraController: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ out: AVCaptureOutput,
                                   didOutput sampleBuffer: CMSampleBuffer,
                                   from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        var ci = CIImage(cvPixelBuffer: buffer)
        // Back camera lands rotated; portrait-only app so this is a fixed turn.
        ci = ci.oriented(.right)

        Task { @MainActor in
            let g = self.grade

            let fast = g.applyFast(to: ci)
            if let cg = GradeEngine.context.createCGImage(fast, from: fast.extent) {
                self.preview = cg
            }
        }
    }
}

extension CameraController: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput,
                                 didFinishProcessingPhoto photo: AVCapturePhoto,
                                 error: Error?) {
        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let captured = UIImage(data: data) else { return }

        Task { @MainActor in
            guard let pending = self.pendingCapture else { return }
            self.pendingCapture = nil
            let ci = CIImage(image: captured)?.oriented(.right)
            if let ci, let graded = self.grade.render(ci) { pending(graded) }
        }
    }
}

// MARK: - Shooting screen

struct RollCameraView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var cam = CameraController()
    @ObservedObject private var roll = RollStore.shared

    @State private var grade: Grade = .daydream
    @State private var flash = false
    @State private var shotCount = 0
    @State private var importing = false
    @AppStorage("askedRollNotifications") private var askedForNotifications = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let cg = cam.preview {
                Image(decorative: cg, scale: 1, orientation: .up)
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
                    .clipped()
            } else {
                unavailableState
            }

            // The shutter flash — the only confirmation you get, since the
            // frame itself is sealed the instant it's taken.
            if flash {
                Color.white.ignoresSafeArea().transition(.opacity)
            }

            VStack {
                header
                Spacer()
                controls
            }
        }
        .statusBarHidden()
        .onAppear { cam.grade = grade; cam.start() }
        .onDisappear { cam.stop() }
        .onChange(of: grade) { _, new in cam.grade = new }
        .photosPicker(isPresented: $importing, selection: $picked, matching: .images)
        .onChange(of: picked) { _, item in Task { await importPicked(item) } }
    }

    @State private var picked: PhotosPickerItem?

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Kicker(text: "The Roll · sealed", color: Ink.gold)
                Text(shotCount == 0 ? "SHOOT THE WEEK" : "\(shotCount) THIS SESSION")
                    .font(.display(19))
                    .foregroundStyle(.white)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(.ultraThinMaterial, in: Circle())
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    private var controls: some View {
        VStack(spacing: 20) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Grade.all) { g in
                        Button { grade = g } label: {
                            VStack(spacing: 3) {
                                Text(g.name)
                                    .font(.mono(9, .bold)).tracking(1.4)
                                Text(g.note)
                                    .font(.mono(7)).tracking(0.4)
                                    .opacity(0.65)
                            }
                            .foregroundStyle(grade == g ? .black : .white)
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .background(grade == g ? Ink.gold : Color.white.opacity(0.14), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }

            HStack(spacing: 34) {
                Button { importing = true } label: {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 18))
                        .foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                        .background(.white.opacity(0.12), in: Circle())
                }

                Button(action: shoot) {
                    ZStack {
                        Circle().strokeBorder(Ink.gold, lineWidth: 3).frame(width: 78, height: 78)
                        Circle().fill(Ink.gold).frame(width: 62, height: 62)
                    }
                }
                .disabled(cam.preview == nil)
                .opacity(cam.preview == nil ? 0.35 : 1)

                // Balances the row; the roll can't be opened from here by design.
                Image(systemName: "lock.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(width: 46, height: 46)
                    .background(.white.opacity(0.06), in: Circle())
            }

            Text("develops \(developLabel)")
                .font(.mono(9, .semibold)).tracking(2)
                .foregroundStyle(.white.opacity(0.55))
                .padding(.bottom, 26)
        }
    }

    private var unavailableState: some View {
        VStack(spacing: 14) {
            Image(systemName: cam.authorized ? "camera.fill" : "camera.metering.unknown")
                .font(.system(size: 30))
                .foregroundStyle(Ink.gold.opacity(0.8))
            Text(cam.unavailable ? "NO CAMERA HERE"
                 : cam.authorized ? "OPENING THE SHUTTER…" : "CAMERA ACCESS OFF")
                .font(.mono(11, .bold)).tracking(2.4)
                .foregroundStyle(.white)
            Text(cam.unavailable
                 ? "Running on a simulator. Import a frame instead — it seals the same way."
                 : cam.authorized ? "One second."
                 : "Turn the camera on in Settings to shoot the week.")
                .font(.body_(13))
                .multilineTextAlignment(.center)
                .foregroundStyle(Ink.mist)
                .padding(.horizontal, 46)
        }
    }

    private var developLabel: String {
        let d = RollStore.developDate(for: Date())
        let f = DateFormatter()
        f.dateFormat = "EEEE 'at' h:mm a"
        return f.string(from: d).lowercased()
    }

    private func shoot() {
        cam.capture { image in
            roll.add(image, grade: grade)
            askForNotificationsOnce()
            shotCount += 1
            withAnimation(.easeOut(duration: 0.08)) { flash = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) {
                withAnimation(.easeIn(duration: 0.22)) { flash = false }
            }
        }
    }

    private func importPicked(_ item: PhotosPickerItem?) async {
        guard let item,
              let data = try? await item.loadTransferable(type: Data.self),
              let ui = UIImage(data: data) else { return }
        roll.add(ui, grade: grade)
        askForNotificationsOnce()
        shotCount += 1
        picked = nil
    }

    /// Asked once, and only after there's actually something in the roll worth
    /// being told about on Saturday.
    private func askForNotificationsOnce() {
        guard !askedForNotifications else { return }
        askedForNotifications = true
        roll.requestNotifications()
    }
}
