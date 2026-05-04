import AppKit
import HotKey
import SwiftUI

/// A persisted global keyboard shortcut binding. Stores the carbon key code
/// plus modifier flags plus the unshifted character (so we can render
/// `Shift+/` as `⌃⌥?` instead of `⌃⌥⇧/`).
struct ShortcutBinding: Codable, Equatable {
    var keyCode: UInt32
    var modifierFlagsRaw: UInt
    var charactersIgnoringModifiers: String

    /// Default for the toggle-listening hotkey: `⌃⌥?` (Control + Option + Shift + `/`).
    /// `?` requires Shift on US layouts; we add Control + Option so the binding
    /// is safe to use globally without consuming every `?` you type.
    static let defaultBinding = ShortcutBinding(
        keyCode: 0x2C, // kVK_ANSI_Slash
        modifierFlagsRaw: NSEvent.ModifierFlags([.control, .option, .shift]).rawValue,
        charactersIgnoringModifiers: "/"
    )

    /// Default for show / hide HUD: `⌃⌥H`.
    static let defaultShowHideBinding = ShortcutBinding(
        keyCode: 0x04, // kVK_ANSI_H
        modifierFlagsRaw: NSEvent.ModifierFlags([.control, .option]).rawValue,
        charactersIgnoringModifiers: "h"
    )

    /// Default for new-interview reset: `⌃⌥N`.
    static let defaultNewInterviewBinding = ShortcutBinding(
        keyCode: 0x2D, // kVK_ANSI_N
        modifierFlagsRaw: NSEvent.ModifierFlags([.control, .option]).rawValue,
        charactersIgnoringModifiers: "n"
    )

    var modifiers: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifierFlagsRaw)
            .intersection(.deviceIndependentFlagsMask)
    }

    var hotKeyKey: Key? {
        Key(carbonKeyCode: keyCode)
    }

    var displayString: String {
        var result = ""
        if modifiers.contains(.control) { result += "⌃" }
        if modifiers.contains(.option)  { result += "⌥" }
        if modifiers.contains(.command) { result += "⌘" }

        if modifiers.contains(.shift),
           let shifted = Self.shiftedCharacter(for: charactersIgnoringModifiers) {
            // shift is implicit in shifted character — don't render ⇧
            result += shifted
        } else {
            if modifiers.contains(.shift) { result += "⇧" }
            result += keyCharacter
        }
        return result
    }

    private var keyCharacter: String {
        if charactersIgnoringModifiers.isEmpty {
            return Self.specialKeyName(for: keyCode) ?? "?"
        }
        // Single letter → uppercase; punctuation/digit → as is
        if charactersIgnoringModifiers.count == 1,
           let scalar = charactersIgnoringModifiers.unicodeScalars.first,
           CharacterSet.letters.contains(scalar) {
            return charactersIgnoringModifiers.uppercased()
        }
        return charactersIgnoringModifiers
    }

    private static func shiftedCharacter(for s: String) -> String? {
        let map: [String: String] = [
            "/": "?", ",": "<", ".": ">", ";": ":", "'": "\"",
            "1": "!", "2": "@", "3": "#", "4": "$", "5": "%",
            "6": "^", "7": "&", "8": "*", "9": "(", "0": ")",
            "-": "_", "=": "+", "[": "{", "]": "}", "\\": "|",
            "`": "~"
        ]
        return map[s]
    }

    /// Names for keys that don't have an obvious printed character.
    private static func specialKeyName(for keyCode: UInt32) -> String? {
        // Common Carbon key codes for special keys
        switch keyCode {
        case 0x33: return "⌫"     // Delete
        case 0x35: return "⎋"     // Escape
        case 0x24: return "↩"     // Return
        case 0x4C: return "⌤"     // Enter
        case 0x30: return "⇥"     // Tab
        case 0x31: return "Space"
        case 0x7B: return "←"
        case 0x7C: return "→"
        case 0x7D: return "↓"
        case 0x7E: return "↑"
        case 0x7A: return "F1"
        case 0x78: return "F2"
        case 0x63: return "F3"
        case 0x76: return "F4"
        case 0x60: return "F5"
        case 0x61: return "F6"
        case 0x62: return "F7"
        case 0x64: return "F8"
        case 0x65: return "F9"
        case 0x6D: return "F10"
        case 0x67: return "F11"
        case 0x6F: return "F12"
        default:   return nil
        }
    }
}

// MARK: - Recorder UI

/// SwiftUI control to record a new shortcut. Click to enter capture mode,
/// then press a key combo. ESC cancels. Requires at least one of ⌃ ⌥ ⌘.
struct ShortcutRecorder: View {
    @Binding var binding: ShortcutBinding
    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var hint: String?

    var body: some View {
        Button(action: toggle) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(isRecording ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.15))
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(isRecording ? Color.accentColor : Color.clear, lineWidth: 1.5)
                Text(isRecording ? (hint ?? "Press keys…") : binding.displayString)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.primary)
            }
            .frame(minWidth: 110, minHeight: 26)
            .fixedSize()
        }
        .buttonStyle(.plain)
        .onDisappear { stopRecording() }
    }

    private func toggle() {
        if isRecording { stopRecording() } else { startRecording() }
    }

    private func startRecording() {
        guard !isRecording else { return }
        isRecording = true
        hint = nil
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            // ESC cancels
            if event.keyCode == 53 {
                stopRecording()
                return nil
            }

            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let modKeys: NSEvent.ModifierFlags = [.control, .option, .command]

            // Require at least one of ⌃ ⌥ ⌘ — bare keys would conflict with
            // ordinary typing.
            if modifiers.intersection(modKeys).isEmpty {
                hint = "needs ⌃ ⌥ or ⌘"
                NSSound.beep()
                return nil
            }

            let chars = event.charactersIgnoringModifiers ?? ""
            binding = ShortcutBinding(
                keyCode: UInt32(event.keyCode),
                modifierFlagsRaw: modifiers.rawValue,
                charactersIgnoringModifiers: chars
            )
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        hint = nil
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
    }
}
