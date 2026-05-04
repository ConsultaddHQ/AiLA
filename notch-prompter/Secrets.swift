import Foundation

/// Reads API keys from a `Secrets.plist` bundled inside the app at build time.
/// The plist is gitignored — only present in private team builds produced by
/// `scripts/build-team-release.sh`. Public-source builds have no `Secrets.plist`,
/// so `value(for:)` returns nil and the user is expected to paste keys via
/// Settings → API Keys (which writes to Keychain).
enum Secrets {

    private static let plistKeys: [KeychainAccount: String] = [
        .anthropic: "ANTHROPIC_API_KEY",
        .elevenLabs: "ELEVENLABS_API_KEY"
    ]

    static func value(for account: KeychainAccount) -> String? {
        guard
            let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
            let data = try? Data(contentsOf: url),
            let plist = try? PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            ) as? [String: Any],
            let key = plistKeys[account],
            let value = plist[key] as? String,
            !value.isEmpty
        else { return nil }
        return value
    }

    /// `true` when the running build was produced with bundled team keys.
    static var hasBundledKeys: Bool {
        Bundle.main.url(forResource: "Secrets", withExtension: "plist") != nil
    }
}
