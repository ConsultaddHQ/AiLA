import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
import ScreenCaptureKit

enum AudioCaptureError: Error, LocalizedError {
    case permissionDenied
    case noContentAvailable
    case streamStartFailed(Error)
    case fileCreationFailed
    case noActiveRecording

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Screen Recording permission is required so the app can hear interview audio. Grant it in System Settings → Privacy & Security → Screen & System Audio Recording, then restart the app."
        case .noContentAvailable:
            return "No display found to capture system audio from."
        case .streamStartFailed(let e):
            return "Could not start audio capture: \(e.localizedDescription)"
        case .fileCreationFailed:
            return "Could not create the audio file for this recording."
        case .noActiveRecording:
            return "No active recording."
        }
    }
}

/// Captures system audio (everything currently playing through the Mac's
/// output mix — typically the interviewer's voice on Zoom/Meet/Teams) using
/// ScreenCaptureKit. No virtual audio cable required.
///
/// Requires the user to grant Screen Recording permission once in System
/// Settings → Privacy & Security → Screen & System Audio Recording.
final class AudioCapture {
    private var stream: SCStream?
    private var output: AudioStreamOutput?
    private(set) var currentURL: URL?

    // MARK: - Permission helpers

    /// True when Screen Recording permission is already granted.
    static func hasScreenRecordingPermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Triggers the system permission prompt the first time. Returns the
    /// result the OS reports synchronously. Note: macOS often requires an
    /// app relaunch before a freshly-granted permission becomes visible to
    /// `CGPreflightScreenCaptureAccess`, so callers should be prepared to
    /// surface a "restart the app" message even on a `true` return.
    @discardableResult
    static func requestScreenRecordingPermission() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    // MARK: - Capture lifecycle

    @discardableResult
    func start() async throws -> URL {
        if stream != nil { await stopInternal() }

        guard Self.hasScreenRecordingPermission() else {
            throw AudioCaptureError.permissionDenied
        }

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw AudioCaptureError.streamStartFailed(error)
        }
        guard let display = content.displays.first else {
            throw AudioCaptureError.noContentAvailable
        }

        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])

        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48000
        config.channelCount = 2
        // Audio-only: SCStream still requires *some* video config; keep it
        // minimal so we don't pay for frames we never consume.
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.queueDepth = 6
        config.showsCursor = false

        let dir = try Self.cachesDirectory()
        let url = dir.appendingPathComponent("interview-\(Int(Date().timeIntervalSince1970)).wav")
        let newOutput = AudioStreamOutput(targetURL: url)

        let newStream = SCStream(filter: filter, configuration: config, delegate: nil)
        do {
            try newStream.addStreamOutput(
                newOutput,
                type: .audio,
                sampleHandlerQueue: DispatchQueue(label: "com.notchprompter.audio.sc-output", qos: .userInteractive)
            )
            try await newStream.startCapture()
        } catch {
            throw AudioCaptureError.streamStartFailed(error)
        }

        self.stream = newStream
        self.output = newOutput
        self.currentURL = url
        return url
    }

    func stop() async throws -> URL {
        guard let url = currentURL else { throw AudioCaptureError.noActiveRecording }
        await stopInternal()
        return url
    }

    private func stopInternal() async {
        if let s = stream {
            try? await s.stopCapture()
        }
        output?.close()
        stream = nil
        output = nil
        currentURL = nil
    }

    private static func cachesDirectory() throws -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("notch-prompter", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

// MARK: - SCStream output handler

private final class AudioStreamOutput: NSObject, SCStreamOutput {
    private let targetURL: URL
    private var audioFile: AVAudioFile?
    private let queue = DispatchQueue(label: "com.notchprompter.audio.file-write")

    init(targetURL: URL) {
        self.targetURL = targetURL
        super.init()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid else { return }
        guard let pcmBuffer = sampleBuffer.asPCMBuffer else { return }

        queue.async { [weak self] in
            guard let self = self else { return }
            if self.audioFile == nil {
                // Lazy-init the file with the exact format the system gives us,
                // so we never have to convert in the hot path.
                self.audioFile = try? AVAudioFile(forWriting: self.targetURL, settings: pcmBuffer.format.settings)
            }
            try? self.audioFile?.write(from: pcmBuffer)
        }
    }

    /// Flush + release the file. Called from `AudioCapture.stopInternal()`.
    func close() {
        queue.sync {
            audioFile = nil
        }
    }
}

// MARK: - CMSampleBuffer → AVAudioPCMBuffer

private extension CMSampleBuffer {
    var asPCMBuffer: AVAudioPCMBuffer? {
        try? withAudioBufferList { audioBufferList, _ -> AVAudioPCMBuffer? in
            guard let absd = formatDescription?.audioStreamBasicDescription else { return nil }
            guard let format = AVAudioFormat(
                standardFormatWithSampleRate: absd.mSampleRate,
                channels: absd.mChannelsPerFrame
            ) else { return nil }
            return AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: audioBufferList.unsafePointer)
        }
    }
}
