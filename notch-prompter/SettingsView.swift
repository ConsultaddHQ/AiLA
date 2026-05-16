import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: InterviewViewModel

    var body: some View {
        TabView {
            AudioSettingsTab(viewModel: viewModel)
                .tabItem { Label("Audio", systemImage: "mic") }

            InterviewSetupTab(viewModel: viewModel)
                .tabItem { Label("Interview", systemImage: "person.2.wave.2") }

            APIKeysSettingsTab()
                .tabItem { Label("API Keys", systemImage: "key") }

            AppearanceSettingsTab(viewModel: viewModel)
                .tabItem { Label("Appearance", systemImage: "paintpalette") }

            LayoutSettingsTab(viewModel: viewModel)
                .tabItem { Label("Layout", systemImage: "rectangle.3.offgrid") }

            ShortcutsSettingsTab(viewModel: viewModel)
                .tabItem { Label("Shortcuts", systemImage: "command") }
        }
        .frame(width: 560, height: 460)
        .overlay(alignment: .bottom) {
            Text(AppVersion.display)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .padding(.bottom, 6)
        }
        .alert("Screen Recording Permission Needed",
               isPresented: $viewModel.showScreenRecordingAlert) {
            Button("Open System Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                    NSWorkspace.shared.open(url)
                }
            }
            Button("OK", role: .cancel) { }
        } message: {
            Text("NotchPrompter listens to system audio (everything playing through your Mac's output) so it can hear the interviewer. macOS gates that under Screen Recording permission. Grant it in System Settings → Privacy & Security → Screen & System Audio Recording, then quit and relaunch the app.")
        }
    }
}

// MARK: - Audio

private struct AudioSettingsTab: View {
    @ObservedObject var viewModel: InterviewViewModel
    @State private var hasPermission: Bool = AudioCapture.hasScreenRecordingPermission()

    var body: some View {
        Form {
            Section {
                HStack(alignment: .firstTextBaseline) {
                    Text("Audio source")
                    Spacer()
                    Text("System audio (entire Mac mix)")
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("Capture")
            } footer: {
                Text("The app uses Apple's ScreenCaptureKit to listen to whatever your Mac is playing — typically the interviewer's voice on Zoom, Meet, or Teams. Your microphone is not captured. No virtual audio cable needs to be installed.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                HStack(alignment: .firstTextBaseline) {
                    if hasPermission {
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    } else {
                        Label("Not granted", systemImage: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                    }
                    Spacer()
                    Button("Refresh") { hasPermission = AudioCapture.hasScreenRecordingPermission() }
                        .controlSize(.small)
                    Button("Open System Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .controlSize(.small)
                }
            } header: {
                Text("Screen Recording permission")
            } footer: {
                Text("Required by macOS for system audio capture. Grant once in System Settings → Privacy & Security → Screen & System Audio Recording, then quit and relaunch the app for the new permission to take effect.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .onAppear { hasPermission = AudioCapture.hasScreenRecordingPermission() }
    }
}

// MARK: - Interview Setup

private struct InterviewSetupTab: View {
    @ObservedObject var viewModel: InterviewViewModel

    var body: some View {
        Form {
            Section {
                TextField("Name (optional)", text: $viewModel.interviewSetup.interviewerName)
                    .textFieldStyle(.roundedBorder)
                TextField("Company (e.g. JP Morgan, Eli Lilly, Walmart)", text: $viewModel.interviewSetup.interviewerCompany)
                    .textFieldStyle(.roundedBorder)
            } header: {
                Text("Who's interviewing you?")
            } footer: {
                Text("The interviewer's company is the most important field — it sets the domain language used in every answer (finance, pharma, retail, etc.).")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section {
                TextField("Current employer", text: $viewModel.interviewSetup.currentEmployer)
                    .textFieldStyle(.roundedBorder)
                TextField("Current project / role (one sentence)", text: $viewModel.interviewSetup.currentProject)
                    .textFieldStyle(.roundedBorder)
            } header: {
                Text("Where do you work now?")
            }

            Section {
                TextEditor(text: $viewModel.interviewSetup.pastCompanies)
                    .font(.system(size: 12))
                    .frame(minHeight: 90)
                Text("One company per line. Keep each line short.\nExample:\nAcmeCo — built ML pipeline\nFoobarCorp — led platform team")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("One or two past companies")
            }

            Section {
                if viewModel.interviewSetup.isComplete {
                    Label("Setup complete — ready for the interview.", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                } else {
                    Label("Add at least the interviewer's company and your current employer.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.caption)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - API Keys

private struct APIKeysSettingsTab: View {
    @State private var anthropicKey: String = Keychain.get(.anthropic) ?? ""
    @State private var elevenLabsKey: String = Keychain.get(.elevenLabs) ?? ""
    @State private var anthropicSaved: Bool = false
    @State private var elevenLabsSaved: Bool = false

    var body: some View {
        Form {
            if Credentials.hasBundledKeys {
                Section {
                    Label("Keys are bundled with this build.", systemImage: "checkmark.seal.fill")
                        .foregroundColor(.green)
                    Text("This is a team build — Anthropic and ElevenLabs keys are baked into the app and used automatically. You can override either one below if you want to use your own; an override saved here takes priority over the bundled key.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section {
                SecureField("sk-ant-…", text: $anthropicKey)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("Save Anthropic key") { saveAnthropic() }
                        .disabled(anthropicKey.isEmpty)
                    if anthropicSaved {
                        Label("Saved to Keychain", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                    }
                }
                Link("Get an Anthropic API key →", destination: URL(string: "https://console.anthropic.com/settings/keys")!)
                    .font(.caption)
            } header: {
                Text("Anthropic")
            } footer: {
                Text("Used for keyword answer generation (claude-haiku-4-5). Stored in macOS Keychain.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section {
                SecureField("xi-api-key…", text: $elevenLabsKey)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("Save ElevenLabs key") { saveElevenLabs() }
                        .disabled(elevenLabsKey.isEmpty)
                    if elevenLabsSaved {
                        Label("Saved to Keychain", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                    }
                }
                Link("Get an ElevenLabs API key →", destination: URL(string: "https://elevenlabs.io/app/settings/api-keys")!)
                    .font(.caption)
            } header: {
                Text("ElevenLabs")
            } footer: {
                Text("Used for transcribing the interviewer's question (Scribe v1). Stored in macOS Keychain.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func saveAnthropic() {
        do {
            try Keychain.set(anthropicKey, for: .anthropic)
            anthropicSaved = true
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                anthropicSaved = false
            }
        } catch {
            anthropicSaved = false
        }
    }

    private func saveElevenLabs() {
        do {
            try Keychain.set(elevenLabsKey, for: .elevenLabs)
            elevenLabsSaved = true
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                elevenLabsSaved = false
            }
        } catch {
            elevenLabsSaved = false
        }
    }
}

// MARK: - Appearance

private struct AppearanceSettingsTab: View {
    @ObservedObject var viewModel: InterviewViewModel

    var body: some View {
        Form {
            Section("Theme") {
                Picker("Theme", selection: $viewModel.theme) {
                    ForEach(PrompterTheme.allCases) { t in
                        Text(t.displayName).tag(t)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Typography") {
                Picker("Font design", selection: $viewModel.fontDesign) {
                    Text(Font.Design.default.displayLocalizedName).tag(Font.Design.default)
                    Text(Font.Design.serif.displayLocalizedName).tag(Font.Design.serif)
                    Text(Font.Design.rounded.displayLocalizedName).tag(Font.Design.rounded)
                    Text(Font.Design.monospaced.displayLocalizedName).tag(Font.Design.monospaced)
                }
                .pickerStyle(.menu)

                HStack {
                    Text("Font size")
                    Slider(value: $viewModel.fontSize, in: 12...28, step: 1)
                    Text("\(Int(viewModel.fontSize))")
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                        .frame(width: 28, alignment: .trailing)
                }
            }

            Section("Opacity") {
                HStack {
                    Slider(value: $viewModel.hudOpacity, in: 0.5...1.0, step: 0.05)
                    Text("\(Int(viewModel.hudOpacity * 100))%")
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                        .frame(width: 40, alignment: .trailing)
                }
            }

            Section {
                Toggle("Use OpenDyslexic font", isOn: $viewModel.useDyslexiaFriendlyFont)
                if viewModel.useDyslexiaFriendlyFont {
                    Text("Bundled OFL-licensed font designed to reduce letter confusion. Overrides the Font design selection above when on.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text("Accessibility")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Layout

private struct LayoutSettingsTab: View {
    @ObservedObject var viewModel: InterviewViewModel

    var body: some View {
        Form {
            Section("Position") {
                Picker("Horizontal alignment", selection: $viewModel.horizontalAlignment) {
                    ForEach(PrompterHorizontalAlignment.allCases) { a in
                        Text(a.displayName).tag(a)
                    }
                }
                .pickerStyle(.segmented)

                let screens = NSScreen.screens
                Picker("Display", selection: $viewModel.selectedScreenIndex) {
                    ForEach(0..<screens.count, id: \.self) { idx in
                        Text(screenName(screens[idx], idx: idx)).tag(idx)
                    }
                }
                .pickerStyle(.menu)
            }

            Section {
                HStack {
                    Text("Width")
                    Slider(value: $viewModel.hudWidth, in: 280...1100, step: 10)
                    Text("\(Int(viewModel.hudWidth))pt")
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                        .frame(width: 56, alignment: .trailing)
                }
                HStack {
                    Text("Height")
                    Slider(value: $viewModel.hudHeight, in: 120...600, step: 10)
                    Text("\(Int(viewModel.hudHeight))pt")
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                        .frame(width: 56, alignment: .trailing)
                }
            } header: {
                Text("HUD size")
            } footer: {
                Text("Set the HUD large enough for the longest answer you expect. Width 560pt × Height 320pt is a good starting point; longer prose-style answers may need up to 900×500.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Privacy") {
                Toggle("Hide HUD from screen recording", isOn: $viewModel.hideFromScreenRecording)
                Text("When enabled, the HUD does not appear in screen recordings or shared screens (e.g. Zoom share-screen). Recommended for interviews.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func screenName(_ screen: NSScreen, idx: Int) -> String {
        let name = screen.localizedName.isEmpty ? "Display \(idx + 1)" : screen.localizedName
        if screen == NSScreen.main { return "\(name) (Main)" }
        return name
    }
}

// MARK: - Shortcuts

private struct ShortcutsSettingsTab: View {
    @ObservedObject var viewModel: InterviewViewModel

    var body: some View {
        Form {
            Section {
                ShortcutRow(
                    label: "Toggle listening",
                    binding: $viewModel.hotkeyBinding,
                    defaultBinding: .defaultBinding
                )
                ShortcutRow(
                    label: "Show / hide HUD",
                    binding: $viewModel.showHideHotkeyBinding,
                    defaultBinding: .defaultShowHideBinding
                )
                ShortcutRow(
                    label: "New interview",
                    binding: $viewModel.newInterviewHotkeyBinding,
                    defaultBinding: .defaultNewInterviewBinding
                )
            } header: {
                Text("Global shortcuts")
            } footer: {
                Text("Click any field, then press your desired key combination. Each combo must include at least one of ⌃ ⌥ ⌘ so it doesn't conflict with ordinary typing. Press ESC while recording to cancel.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section {
                Text("• Toggle listening starts capture; press again to stop and process.\n• Show/hide the HUD without going through the menu bar.\n• New interview wipes the conversation history so the LLM doesn't carry stale context into the next session.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }
}

private struct ShortcutRow: View {
    let label: String
    @Binding var binding: ShortcutBinding
    let defaultBinding: ShortcutBinding

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
            Spacer()
            ShortcutRecorder(binding: $binding)
            Button {
                binding = defaultBinding
            } label: {
                Image(systemName: "arrow.uturn.backward.circle")
            }
            .buttonStyle(.plain)
            .help("Reset to default (\(defaultBinding.displayString))")
        }
    }
}
