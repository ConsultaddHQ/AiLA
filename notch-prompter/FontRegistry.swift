import AppKit
import CoreText
import Foundation
import SwiftUI

/// Registers app-bundled OpenType fonts at launch so SwiftUI can reference
/// them by PostScript name via `Font.custom(...)`.
enum FontRegistry {
    /// Call once from `AppDelegate.applicationDidFinishLaunching`.
    static func registerBundledFonts() {
        let names = [
            "OpenDyslexic-Regular",
            "OpenDyslexic-Bold",
            "OpenDyslexic-Italic",
            "OpenDyslexic-Bold-Italic"
        ]
        for name in names {
            register(resource: name, ext: "otf")
        }

        #if DEBUG
        let registered = NSFontManager.shared.availableFonts.filter {
            $0.localizedCaseInsensitiveContains("opendyslexic")
        }
        print("[FontRegistry] OpenDyslexic faces registered: \(registered)")
        #endif
    }

    private static func register(resource: String, ext: String) {
        guard let url = Bundle.main.url(forResource: resource, withExtension: ext) else {
            #if DEBUG
            print("[FontRegistry] missing bundle resource: \(resource).\(ext)")
            #endif
            return
        }
        var error: Unmanaged<CFError>?
        let success = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        if !success {
            #if DEBUG
            let detail = error?.takeRetainedValue().localizedDescription ?? "unknown"
            print("[FontRegistry] failed to register \(resource): \(detail)")
            #else
            _ = error?.release()
            #endif
        }
    }
}

/// Resolves a SwiftUI `Font` for the HUD, switching between the system font
/// and OpenDyslexic depending on the user's accessibility preference.
enum HUDFont {
    static func font(
        size: CGFloat,
        weight: Font.Weight,
        italic: Bool,
        useDyslexicFriendly: Bool,
        systemDesign: Font.Design
    ) -> Font {
        if useDyslexicFriendly {
            let name = openDyslexicFaceName(weight: weight, italic: italic)
            return Font.custom(name, size: size)
        }
        var f = Font.system(size: size, weight: weight, design: systemDesign)
        if italic { f = f.italic() }
        return f
    }

    private static func openDyslexicFaceName(weight: Font.Weight, italic: Bool) -> String {
        let isBold: Bool = {
            switch weight {
            case .bold, .heavy, .black, .semibold: return true
            default: return false
            }
        }()
        switch (isBold, italic) {
        case (true,  true):  return "OpenDyslexic-Bold-Italic"
        case (true,  false): return "OpenDyslexic-Bold"
        case (false, true):  return "OpenDyslexic-Italic"
        case (false, false): return "OpenDyslexic-Regular"
        }
    }
}
