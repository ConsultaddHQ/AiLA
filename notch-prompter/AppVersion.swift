import Foundation

/// Human-readable build identity, surfaced in the menu bar dropdown and
/// Settings so you can tell at a glance which build is running.
///
/// **Bump `label` and `buildDate` on every meaningful change** that gets
/// rebuilt and tested. The whole point is that the string visible in the app
/// matches the change you just made — if they don't match, you're running a
/// stale binary and need a clean rebuild (see scripts/clean-rebuild.sh).
enum AppVersion {
    static let marketing = "0.6.0"
    static let label = "question-placeholder"
    static let buildDate = "2026-05-15"

    /// e.g. "AiLA 0.5.0 · thinking-stream · 2026-05-14"
    static var display: String {
        "AiLA \(marketing) · \(label) · \(buildDate)"
    }

    /// Short form for tight spaces, e.g. "0.5.0 (thinking-stream)"
    static var short: String {
        "\(marketing) (\(label))"
    }
}
