import Combine
import Foundation
import HotKey
import SwiftUI

enum InterviewState: Equatable {
    case idle
    case listening
    case transcribing
    case thinking
    case answering(InterviewAnswer)
    case error(message: String)

    static func == (lhs: InterviewState, rhs: InterviewState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.listening, .listening), (.transcribing, .transcribing), (.thinking, .thinking):
            return true
        case (.answering(let a), .answering(let b)): return a == b
        case (.error(let a), .error(let b)): return a == b
        default: return false
        }
    }
}

/// A streaming-aware Interview Ace answer. `rawText` grows as tokens arrive.
/// The parsed sections (lead / beats / closer / runway) are computed from
/// the raw text and update progressively as the stream comes in.
struct InterviewAnswer: Equatable {
    let question: String
    var rawText: String
    var isComplete: Bool

    var parsed: ParsedAnswer {
        AnswerParser.parse(rawText)
    }
}

/// Structured view of the Interview Ace output.
struct ParsedAnswer: Equatable {
    var lead: String = ""
    var beats: [String] = []
    var closer: String = ""
    var runway: [String] = []

    /// True once at least one section is filled in. Used to decide whether
    /// the HUD has anything worth rendering yet.
    var hasContent: Bool {
        !lead.isEmpty || !beats.isEmpty || !closer.isEmpty || !runway.isEmpty
    }
}

/// Parses the structured output produced by the Interview Ace prompt:
///
///     LEAD: One sentence.
///     BEATS:
///     - first beat
///     - second beat
///     CLOSER: Punch line.
///     RUNWAY: idempotency · schema · cost ceiling
///
/// Tolerates partial input — during streaming, sections fill in as they arrive.
enum AnswerParser {
    static func parse(_ raw: String) -> ParsedAnswer {
        var result = ParsedAnswer()
        var currentSection: Section?
        var leadBuffer: [String] = []
        var closerBuffer: [String] = []
        var runwayBuffer: [String] = []

        for rawLine in raw.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if let (section, value) = matchHeader(line: trimmed) {
                currentSection = section
                switch section {
                case .lead:
                    leadBuffer = value.isEmpty ? [] : [value]
                case .beats:
                    result.beats = []
                case .closer:
                    closerBuffer = value.isEmpty ? [] : [value]
                case .runway:
                    runwayBuffer = value.isEmpty ? [] : [value]
                }
                continue
            }

            guard let section = currentSection else { continue }

            switch section {
            case .lead:
                if !trimmed.isEmpty { leadBuffer.append(trimmed) }
            case .beats:
                if let beat = parseBeat(trimmed) { result.beats.append(beat) }
            case .closer:
                if !trimmed.isEmpty { closerBuffer.append(trimmed) }
            case .runway:
                if !trimmed.isEmpty { runwayBuffer.append(trimmed) }
            }
        }

        result.lead = leadBuffer.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        result.closer = closerBuffer.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        result.runway = parseRunway(runwayBuffer.joined(separator: " "))
        return result
    }

    private enum Section {
        case lead, beats, closer, runway
    }

    /// Matches a section header at the start of a line. Tolerant of an
    /// optional leading bullet marker the model may emit.
    private static func matchHeader(line: String) -> (Section, String)? {
        let cleaned = line.drop(while: { "•-* \t".contains($0) })
        for (prefix, section) in headerPrefixes {
            if cleaned.uppercased().hasPrefix(prefix) {
                let value = cleaned.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
                return (section, String(value))
            }
        }
        return nil
    }

    private static let headerPrefixes: [(String, Section)] = [
        ("LEAD:", .lead),
        ("BEATS:", .beats),
        ("CLOSER:", .closer),
        ("RUNWAY:", .runway)
    ]

    private static func parseBeat(_ s: String) -> String? {
        let stripped = s.drop(while: { "•-* \t".contains($0) }).trimmingCharacters(in: .whitespaces)
        return stripped.isEmpty ? nil : String(stripped)
    }

    private static func parseRunway(_ s: String) -> [String] {
        let separators = CharacterSet(charactersIn: "·•|,;")
        return s
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

final class InterviewViewModel: ObservableObject {

    // MARK: - State

    @Published private(set) var state: InterviewState = .idle
    @Published var showScreenRecordingAlert: Bool = false

    /// Verbal bridge phrase the candidate speaks while the main answer is
    /// being prepared. Updated by the parallel Haiku call. Cleared the moment
    /// the main answer's first token arrives.
    @Published var bridge: String?

    // MARK: - Conversation

    @Published private(set) var conversation = ConversationHistory()

    // MARK: - User profile / API

    /// Lightweight per-interview setup (interviewer / current job / past companies).
    @Published var interviewSetup: InterviewSetup = .empty

    // MARK: - Hotkeys

    /// Toggle listening (start/stop the push-to-talk capture).
    @Published var hotkeyBinding: ShortcutBinding = .defaultBinding

    /// Show or hide the HUD overlay globally.
    @Published var showHideHotkeyBinding: ShortcutBinding = .defaultShowHideBinding

    /// Reset the conversation history and start a fresh interview.
    @Published var newInterviewHotkeyBinding: ShortcutBinding = .defaultNewInterviewBinding

    // MARK: - Window / layout

    @Published var isHUDVisible: Bool = true
    @Published var selectedScreenIndex: Int = 0
    @Published var horizontalAlignment: PrompterHorizontalAlignment = .center
    @Published var hideFromScreenRecording: Bool = true
    @Published var hudWidth: CGFloat = 360
    @Published var hudHeight: CGFloat = 200

    // MARK: - Appearance

    @Published var fontSize: Double = 18.0
    @Published var fontDesign: Font.Design = .default
    @Published var theme: PrompterTheme = .dark
    @Published var hudOpacity: Double = 0.95

    /// When true, the HUD renders all answer text in OpenDyslexic instead of
    /// the system font. Bundled OFL-licensed font.
    @Published var useDyslexiaFriendlyFont: Bool = false

    // MARK: - Internals

    private let audioCapture = AudioCapture()
    private let stt = ElevenLabsSTT()
    private let llm = AnthropicClient()
    private var hotKey: HotKey?
    private var showHideHotKey: HotKey?
    private var newInterviewHotKey: HotKey?
    private var cancellables = Set<AnyCancellable>()
    private var streamTask: Task<Void, Never>?

    // MARK: - UserDefaults keys

    private enum K {
        static let isHUDVisible = "InterviewHUDVisible"
        static let selectedScreenIndex = "InterviewSelectedScreenIndex"
        static let horizontalAlignment = "InterviewHorizontalAlignment"
        static let hideFromScreenRecording = "InterviewHideFromScreenRecording"
        static let hudWidth = "InterviewHUDWidth"
        static let hudHeight = "InterviewHUDHeight"
        static let fontSize = "InterviewFontSize"
        static let fontDesign = "InterviewFontDesign"
        static let theme = "InterviewTheme"
        static let hudOpacity = "InterviewHUDOpacity"
        static let hotkeyBinding = "InterviewHotkeyBinding"
        static let showHideHotkey = "InterviewShowHideHotkey"
        static let newInterviewHotkey = "InterviewNewInterviewHotkey"
        static let interviewSetup = "InterviewSetupConfig"
        static let useDyslexiaFriendlyFont = "InterviewUseDyslexiaFont"
    }

    init() {
        loadSettings()
        observeSettingsChanges()
        setupHotkey()
    }

    // MARK: - Public actions

    func toggleListening() {
        switch state {
        case .idle, .answering, .error:
            checkPermissionAndStart()
        case .listening:
            stopListeningAndProcess()
        case .transcribing, .thinking:
            break
        }
    }

    func clear() {
        streamTask?.cancel()
        streamTask = nil
        bridge = nil
        state = .idle
    }

    /// Wipe the conversation log and return to the idle state. Use this between
    /// interviews so the LLM doesn't see stale context.
    func resetInterview() {
        streamTask?.cancel()
        streamTask = nil
        bridge = nil
        conversation.reset()
        state = .idle
    }

    // MARK: - Pipeline

    private func checkPermissionAndStart() {
        if AudioCapture.hasScreenRecordingPermission() {
            startListening()
        } else {
            // Trigger the system prompt the first time. Whether the user
            // grants it or not, the prompt is the moment they can act —
            // we surface our own alert too, with deeper-link guidance,
            // because newly-granted permission needs an app relaunch
            // before `CGPreflightScreenCaptureAccess` reports `true`.
            _ = AudioCapture.requestScreenRecordingPermission()
            showScreenRecordingAlert = true
        }
    }

    private func startListening() {
        streamTask = Task { [weak self] in
            guard let self = self else { return }
            do {
                _ = try await self.audioCapture.start()
                await MainActor.run { self.state = .listening }
            } catch {
                await MainActor.run {
                    self.state = .error(message: error.localizedDescription)
                }
            }
        }
    }

    private func stopListeningAndProcess() {
        let setupSnapshot = interviewSetup
        streamTask = Task { [weak self] in
            guard let self = self else { return }
            let url: URL
            do {
                url = try await self.audioCapture.stop()
            } catch {
                await MainActor.run {
                    self.state = .error(message: error.localizedDescription)
                }
                return
            }
            await MainActor.run {
                // Show the static fallback bridge from the moment STT begins —
                // it covers the awkward gap before Haiku returns its
                // question-aware bridge.
                self.bridge = Self.staticBridges.randomElement()
                self.state = .transcribing
            }
            await self.process(audioURL: url, setup: setupSnapshot)
        }
    }

    private func process(audioURL: URL, setup: InterviewSetup) async {
        let transcript: String
        do {
            transcript = try await stt.transcribe(wavURL: audioURL)
        } catch {
            await MainActor.run { self.bridge = nil }
            await setState(.error(message: error.localizedDescription))
            return
        }

        await MainActor.run {
            self.conversation.appendInterviewer(transcript)
            self.state = .thinking
        }

        let history = await MainActor.run { self.conversation.snapshot() }

        // Fire the question-aware Haiku bridge in parallel. It usually returns
        // before Sonnet's first token; when it does, it replaces the static
        // fallback already on screen. If it fails or times out, the static
        // fallback stays — never blocks the main answer.
        let bridgeTask = Task { [weak self] in
            guard let self = self else { return }
            do {
                let phrase = try await self.llm.generateBridge(history: history, setup: setup)
                let cleaned = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
                if cleaned.isEmpty { return }
                await MainActor.run {
                    // Only update if we're still in the bridge window.
                    if case .thinking = self.state { self.bridge = cleaned }
                    if case .transcribing = self.state { self.bridge = cleaned }
                }
            } catch {
                #if DEBUG
                print("[Bridge] Haiku call failed: \(error)")
                #endif
            }
        }

        var accumulated = ""

        do {
            for try await event in llm.streamAnswer(history: history, setup: setup) {
                if Task.isCancelled { break }
                switch event {
                case .delta(let text):
                    if accumulated.isEmpty {
                        // First token of the main answer — bridge fades.
                        await MainActor.run { self.bridge = nil }
                    }
                    accumulated += text
                    let answer = InterviewAnswer(question: transcript, rawText: accumulated, isComplete: false)
                    await setState(.answering(answer))
                case .usage(let read, let write):
                    #if DEBUG
                    print("[Anthropic] cache_read=\(read) cache_write=\(write)")
                    #endif
                case .done:
                    let finalText = accumulated
                    let answer = InterviewAnswer(question: transcript, rawText: finalText, isComplete: true)
                    await MainActor.run {
                        self.conversation.appendCandidate(finalText)
                        self.state = .answering(answer)
                        self.bridge = nil
                    }
                }
            }
        } catch {
            await MainActor.run { self.bridge = nil }
            await setState(.error(message: error.localizedDescription))
        }

        bridgeTask.cancel()
    }

    /// Small library of formal placeholder bridges shown immediately while the
    /// Haiku question-aware bridge is being generated. Pick is random per turn.
    private static let staticBridges: [String] = [
        "Let me think this through for a moment.",
        "Stepping into this carefully.",
        "Right, on this specifically — let me frame it properly.",
        "There's a particular angle worth walking through here.",
        "Let me make sure I structure the answer well."
    ]

    @MainActor
    private func setState(_ newState: InterviewState) {
        state = newState
    }

    // MARK: - Hotkey

    private func setupHotkey() {
        rebindHotkey()
        rebindShowHideHotkey()
        rebindNewInterviewHotkey()
    }

    private func rebindHotkey() {
        hotKey = nil
        guard let key = hotkeyBinding.hotKeyKey else { return }
        hotKey = HotKey(key: key, modifiers: hotkeyBinding.modifiers)
        hotKey?.keyDownHandler = { [weak self] in
            DispatchQueue.main.async { self?.toggleListening() }
        }
    }

    private func rebindShowHideHotkey() {
        showHideHotKey = nil
        guard let key = showHideHotkeyBinding.hotKeyKey else { return }
        showHideHotKey = HotKey(key: key, modifiers: showHideHotkeyBinding.modifiers)
        showHideHotKey?.keyDownHandler = { [weak self] in
            DispatchQueue.main.async { self?.isHUDVisible.toggle() }
        }
    }

    private func rebindNewInterviewHotkey() {
        newInterviewHotKey = nil
        guard let key = newInterviewHotkeyBinding.hotKeyKey else { return }
        newInterviewHotKey = HotKey(key: key, modifiers: newInterviewHotkeyBinding.modifiers)
        newInterviewHotKey?.keyDownHandler = { [weak self] in
            DispatchQueue.main.async { self?.resetInterview() }
        }
    }

    // MARK: - Settings persistence

    private func loadSettings() {
        let d = UserDefaults.standard

        if d.object(forKey: K.isHUDVisible) != nil {
            isHUDVisible = d.bool(forKey: K.isHUDVisible)
        }
        selectedScreenIndex = d.integer(forKey: K.selectedScreenIndex)
        if let raw = d.string(forKey: K.horizontalAlignment), let v = PrompterHorizontalAlignment(rawValue: raw) {
            horizontalAlignment = v
        }
        if d.object(forKey: K.hideFromScreenRecording) != nil {
            hideFromScreenRecording = d.bool(forKey: K.hideFromScreenRecording)
        }
        let storedWidth = d.double(forKey: K.hudWidth)
        if storedWidth > 0 { hudWidth = CGFloat(storedWidth) }
        let storedHeight = d.double(forKey: K.hudHeight)
        if storedHeight > 0 { hudHeight = CGFloat(storedHeight) }

        let storedFontSize = d.double(forKey: K.fontSize)
        if storedFontSize > 0 { fontSize = storedFontSize }
        if let raw = d.string(forKey: K.fontDesign) {
            switch raw {
            case "default": fontDesign = .default
            case "serif": fontDesign = .serif
            case "rounded": fontDesign = .rounded
            case "monospaced": fontDesign = .monospaced
            default: fontDesign = .default
            }
        }
        if let raw = d.string(forKey: K.theme), let v = PrompterTheme(rawValue: raw) {
            theme = v
        }
        let storedOpacity = d.double(forKey: K.hudOpacity)
        if storedOpacity > 0 { hudOpacity = storedOpacity }

        if let data = d.data(forKey: K.hotkeyBinding),
           let b = try? JSONDecoder().decode(ShortcutBinding.self, from: data) {
            hotkeyBinding = b
        }
        if let data = d.data(forKey: K.showHideHotkey),
           let b = try? JSONDecoder().decode(ShortcutBinding.self, from: data) {
            showHideHotkeyBinding = b
        }
        if let data = d.data(forKey: K.newInterviewHotkey),
           let b = try? JSONDecoder().decode(ShortcutBinding.self, from: data) {
            newInterviewHotkeyBinding = b
        }

        if let data = d.data(forKey: K.interviewSetup),
           let s = try? JSONDecoder().decode(InterviewSetup.self, from: data) {
            interviewSetup = s
        }

        if d.object(forKey: K.useDyslexiaFriendlyFont) != nil {
            useDyslexiaFriendlyFont = d.bool(forKey: K.useDyslexiaFriendlyFont)
        }
    }

    private func observeSettingsChanges() {
        let d = UserDefaults.standard

        $isHUDVisible.dropFirst().sink { d.set($0, forKey: K.isHUDVisible) }.store(in: &cancellables)
        $selectedScreenIndex.dropFirst().sink { d.set($0, forKey: K.selectedScreenIndex) }.store(in: &cancellables)
        $horizontalAlignment.dropFirst().sink { d.set($0.rawValue, forKey: K.horizontalAlignment) }.store(in: &cancellables)
        $hideFromScreenRecording.dropFirst().sink { d.set($0, forKey: K.hideFromScreenRecording) }.store(in: &cancellables)
        $hudWidth.dropFirst().sink { d.set(Double($0), forKey: K.hudWidth) }.store(in: &cancellables)
        $hudHeight.dropFirst().sink { d.set(Double($0), forKey: K.hudHeight) }.store(in: &cancellables)
        $fontSize.dropFirst().sink { d.set($0, forKey: K.fontSize) }.store(in: &cancellables)
        $fontDesign.dropFirst().sink {
            let raw: String
            switch $0 {
            case .default: raw = "default"
            case .serif: raw = "serif"
            case .rounded: raw = "rounded"
            case .monospaced: raw = "monospaced"
            @unknown default: raw = "default"
            }
            d.set(raw, forKey: K.fontDesign)
        }.store(in: &cancellables)
        $theme.dropFirst().sink { d.set($0.rawValue, forKey: K.theme) }.store(in: &cancellables)
        $hudOpacity.dropFirst().sink { d.set($0, forKey: K.hudOpacity) }.store(in: &cancellables)

        $hotkeyBinding.dropFirst().sink { [weak self] binding in
            guard let self = self else { return }
            self.rebindHotkey()
            if let data = try? JSONEncoder().encode(binding) {
                d.set(data, forKey: K.hotkeyBinding)
            }
        }.store(in: &cancellables)

        $showHideHotkeyBinding.dropFirst().sink { [weak self] binding in
            guard let self = self else { return }
            self.rebindShowHideHotkey()
            if let data = try? JSONEncoder().encode(binding) {
                d.set(data, forKey: K.showHideHotkey)
            }
        }.store(in: &cancellables)

        $newInterviewHotkeyBinding.dropFirst().sink { [weak self] binding in
            guard let self = self else { return }
            self.rebindNewInterviewHotkey()
            if let data = try? JSONEncoder().encode(binding) {
                d.set(data, forKey: K.newInterviewHotkey)
            }
        }.store(in: &cancellables)

        $interviewSetup.dropFirst().sink { setup in
            if let data = try? JSONEncoder().encode(setup) {
                d.set(data, forKey: K.interviewSetup)
            }
        }.store(in: &cancellables)

        $useDyslexiaFriendlyFont.dropFirst().sink {
            d.set($0, forKey: K.useDyslexiaFriendlyFont)
        }.store(in: &cancellables)
    }
}
