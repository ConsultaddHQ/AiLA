import Foundation

/// Two-tier credential resolution: Keychain first (per-user override),
/// then bundled `Secrets.plist` (team build fallback).
///
/// This is the only entry point the rest of the app should use to read API
/// keys. `AnthropicClient` and `ElevenLabsSTT` go through here.
enum Credentials {
    static func get(_ account: KeychainAccount) -> String? {
        if let value = Keychain.get(account), !value.isEmpty {
            return value
        }
        return Secrets.value(for: account)
    }

    /// `true` when at least one key resolves from the bundled `Secrets.plist`.
    /// Used by Settings → API Keys to show "keys bundled with this build".
    static var hasBundledKeys: Bool {
        Secrets.hasBundledKeys
    }
}
