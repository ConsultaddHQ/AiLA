import AppKit
import SwiftUI

@main
struct NotchPrompterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(viewModel: appDelegate.viewModel)
                .onAppear { NSApp.setActivationPolicy(.regular) }
                .onDisappear { NSApp.setActivationPolicy(.accessory) }
        }

        MenuBarExtra {
            MenuContent(viewModel: appDelegate.viewModel)
        } label: {
            let image: NSImage = {
                let ratio = $0.size.height / $0.size.width
                $0.size.height = 18
                $0.size.width = 18 / ratio
                $0.isTemplate = true
                return $0
            }(NSImage(named: "MenuBarIcon")!)

            Image(nsImage: image)
                .renderingMode(.template)
        }
        .menuBarExtraStyle(.menu)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let viewModel: InterviewViewModel
    private var notchWindow: NotchWindow!

    override init() {
        // Register bundled fonts BEFORE constructing the view model so the
        // first render can use OpenDyslexic if the user already enabled it.
        FontRegistry.registerBundledFonts()
        self.viewModel = InterviewViewModel()
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        notchWindow = NotchWindow(viewModel: viewModel)
        notchWindow.show()
        NSApp.setActivationPolicy(.accessory)
    }
}

struct MenuContent: View {
    @ObservedObject var viewModel: InterviewViewModel

    var body: some View {
        // Build identity — always visible so you instantly know which build
        // is running. If this doesn't match the change you just made, you're
        // on a stale binary (run scripts/clean-rebuild.sh).
        Text(AppVersion.display)
            .font(.system(size: 11))

        Divider()

        // Note: the global hotkey (configured in Settings → Shortcuts) handles the
        // toggle action. We don't add a SwiftUI .keyboardShortcut here to avoid
        // a stale or duplicate binding when the user customizes the hotkey.
        Button {
            viewModel.toggleListening()
        } label: {
            Label("\(toggleLabelText) (\(viewModel.hotkeyBinding.displayString))",
                  systemImage: toggleIcon)
        }

        Button {
            viewModel.clear()
        } label: {
            Label("Clear", systemImage: "xmark.circle")
        }
        .disabled(!hasAnswerOrError)

        Button {
            viewModel.resetInterview()
        } label: {
            Label("New Interview", systemImage: "arrow.counterclockwise")
        }

        Divider()

        Button {
            viewModel.isHUDVisible.toggle()
        } label: {
            Label(viewModel.isHUDVisible ? "Hide HUD" : "Show HUD",
                  systemImage: viewModel.isHUDVisible ? "eye.slash" : "eye")
        }
        .keyboardShortcut("h", modifiers: [.command, .option])

        Divider()

        SettingsLink {
            Label("Settings", systemImage: "gearshape")
        }
        .keyboardShortcut(",", modifiers: [.command])

        Divider()

        Button("Feedback") {
            if let url = URL(string: "mailto:jakub@jpomykala.com?subject=NotchPrompter%20feedback") {
                NSWorkspace.shared.open(url)
            }
        }

        Button("Project page") {
            if let url = URL(string: "https://notchprompter.com") {
                NSWorkspace.shared.open(url)
            }
        }

        Divider()

        Button(role: .destructive) {
            NSApp.terminate(nil)
        } label: {
            Label("Exit", systemImage: "xmark.circle")
        }
        .keyboardShortcut("q", modifiers: [.command])
    }

    private var toggleLabelText: String {
        switch viewModel.state {
        case .listening: return "Stop Listening"
        case .transcribing, .thinking: return "Processing…"
        default: return "Start Listening"
        }
    }

    private var toggleIcon: String {
        switch viewModel.state {
        case .listening: return "stop.circle"
        case .transcribing, .thinking: return "hourglass"
        default: return "mic"
        }
    }

    private var hasAnswerOrError: Bool {
        switch viewModel.state {
        case .answering, .error: return true
        default: return false
        }
    }
}
