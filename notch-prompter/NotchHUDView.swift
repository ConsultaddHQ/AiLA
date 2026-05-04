import SwiftUI

struct NotchHUDView: View {
    @ObservedObject var vm: InterviewViewModel

    var body: some View {
        ZStack(alignment: .top) {
            background
            content
                .padding(.top, notchTopInset + 6)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
        .frame(width: vm.hudWidth, height: vm.hudHeight)
        .opacity(vm.hudOpacity)
        .onTapGesture {
            // Click only dismisses error states. Answers persist until the next
            // hotkey press starts a new turn — the candidate keeps the answer
            // visible while reading it aloud.
            if case .error = vm.state { vm.clear() }
        }
    }

    private var notchTopInset: CGFloat {
        let screens = NSScreen.screens
        let idx = vm.selectedScreenIndex
        let screen = (idx >= 0 && idx < screens.count) ? screens[idx] : NSScreen.main
        return screen?.safeAreaInsets.top ?? 0
    }

    // MARK: - Content router

    @ViewBuilder
    private var content: some View {
        switch vm.state {
        case .idle:
            Color.clear
        case .listening:
            ListeningIndicator(textColor: foregroundColor)
        case .transcribing, .thinking:
            BridgeView(
                phrase: vm.bridge,
                fontSize: vm.fontSize,
                fontDesign: vm.fontDesign,
                useDyslexicFriendly: vm.useDyslexiaFriendlyFont,
                foregroundColor: foregroundColor,
                mutedColor: mutedColor
            )
        case .answering(let answer):
            AnswerView(
                answer: answer,
                fontSize: vm.fontSize,
                fontDesign: vm.fontDesign,
                useDyslexicFriendly: vm.useDyslexiaFriendlyFont,
                foregroundColor: foregroundColor,
                mutedColor: mutedColor,
                accentColor: accentColor
            )
        case .error(let msg):
            ErrorView(message: msg, color: errorColor)
        }
    }

    // MARK: - Theming

    private var background: some View {
        Group {
            switch vm.theme {
            case .dark:  Color.black
            case .light: Color(white: 0.96)
            }
        }
    }

    private var foregroundColor: Color {
        vm.theme == .dark ? .white : .black
    }

    private var mutedColor: Color {
        vm.theme == .dark ? Color.white.opacity(0.55) : Color.black.opacity(0.6)
    }

    private var accentColor: Color {
        vm.theme == .dark
            ? Color(red: 0.55, green: 0.85, blue: 1.0)   // soft cyan, easy on the eye
            : Color(red: 0.10, green: 0.45, blue: 0.85)  // deeper blue on light bg
    }

    private var errorColor: Color {
        Color(red: 0.95, green: 0.35, blue: 0.35)
    }
}

// MARK: - State subviews

private struct ListeningIndicator: View {
    let textColor: Color
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color.red)
                .frame(width: 10, height: 10)
                .scaleEffect(pulse ? 1.4 : 0.85)
                .opacity(pulse ? 0.6 : 1.0)
                .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: pulse)
            Text("Listening")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(textColor)
            Spacer()
        }
        .onAppear { pulse = true }
    }
}

/// During transcribing + thinking, the candidate sees a single short bridge
/// phrase they can speak aloud. Initially a static fallback; swapped in-place
/// by the question-aware Haiku result the moment it returns.
private struct BridgeView: View {
    let phrase: String?
    let fontSize: Double
    let fontDesign: Font.Design
    let useDyslexicFriendly: Bool
    let foregroundColor: Color
    let mutedColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let phrase = phrase, !phrase.isEmpty {
                Text(phrase)
                    .font(HUDFont.font(
                        size: bridgeFontSize,
                        weight: .semibold,
                        italic: false,
                        useDyslexicFriendly: useDyslexicFriendly,
                        systemDesign: fontDesign
                    ))
                    .foregroundColor(foregroundColor)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .id(phrase)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.25), value: phrase)
            }

            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.mini)
                    .progressViewStyle(.circular)
                Text("preparing answer")
                    .font(.system(size: 10, weight: .regular, design: fontDesign))
                    .foregroundColor(mutedColor.opacity(0.7))
            }

            Spacer(minLength: 0)
        }
    }

    private var bridgeFontSize: CGFloat { max(CGFloat(fontSize) - 2, 14) }
}

/// Renders an Interview-Ace answer as a performance script:
///   - KEYWORDS as a row of pills (anchor cues)
///   - LEAD as the eye-magnet (big, bold)
///   - BEATS as a tight bullet skeleton
///   - CLOSER as the mic-drop line in italics
private struct AnswerView: View {
    let answer: InterviewAnswer
    let fontSize: Double
    let fontDesign: Font.Design
    let useDyslexicFriendly: Bool
    let foregroundColor: Color
    let mutedColor: Color
    let accentColor: Color

    var body: some View {
        let parsed = answer.parsed

        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 8) {
                // Question caption
                if !answer.question.isEmpty {
                    Text(answer.question)
                        .font(font(size: 10, weight: .regular, italic: false))
                        .foregroundColor(mutedColor.opacity(0.85))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                // LEAD — large, bold, the eye-magnet
                if !parsed.lead.isEmpty {
                    Text(parsed.lead)
                        .font(font(size: leadFontSize, weight: .bold, italic: false))
                        .foregroundColor(foregroundColor)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineSpacing(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                // BEATS — story skeleton
                if !parsed.beats.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(parsed.beats.prefix(5).enumerated()), id: \.offset) { _, beat in
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text("▸")
                                    .font(font(size: beatFontSize, weight: .regular, italic: false))
                                    .foregroundColor(accentColor.opacity(0.85))
                                Text(beat)
                                    .font(font(size: beatFontSize, weight: .regular, italic: false))
                                    .foregroundColor(mutedColor)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .lineSpacing(1)
                            }
                        }
                    }
                }

                // CLOSER — italic punchline
                if !parsed.closer.isEmpty {
                    Text("— \(parsed.closer)")
                        .font(font(size: closerFontSize, weight: .regular, italic: true))
                        .foregroundColor(mutedColor.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                        .lineSpacing(1)
                        .padding(.top, 2)
                }

                // RUNWAY — peripheral preview of likely follow-ups
                if !parsed.runway.isEmpty {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("↳")
                            .font(font(size: runwayFontSize, weight: .semibold, italic: false))
                            .foregroundColor(accentColor.opacity(0.7))
                        Text(parsed.runway.joined(separator: " · "))
                            .font(font(size: runwayFontSize, weight: .regular, italic: true))
                            .foregroundColor(mutedColor.opacity(0.75))
                            .fixedSize(horizontal: false, vertical: true)
                            .lineSpacing(1)
                            .lineLimit(2)
                            .truncationMode(.tail)
                    }
                    .padding(.top, 4)
                }

                Spacer(minLength: 0)
            }
        }
        .scrollDisabled(false)
    }

    private func font(size: CGFloat, weight: Font.Weight, italic: Bool) -> Font {
        HUDFont.font(
            size: size,
            weight: weight,
            italic: italic,
            useDyslexicFriendly: useDyslexicFriendly,
            systemDesign: fontDesign
        )
    }

    // Size relationships — scale around the user's `fontSize` setting so the
    // hierarchy stays consistent if they bump it up or down.
    private var leadFontSize: CGFloat   { CGFloat(fontSize) }
    private var beatFontSize: CGFloat   { max(CGFloat(fontSize) - 5, 11) }
    private var closerFontSize: CGFloat { max(CGFloat(fontSize) - 6, 10) }
    private var runwayFontSize: CGFloat { max(CGFloat(fontSize) - 7, 9) }
}

private struct ErrorView: View {
    let message: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(color)
            Text(message)
                .font(.system(size: 12))
                .foregroundColor(color)
                .lineLimit(3)
            Spacer()
        }
    }
}
