import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Finder tag colour indices (1–7) as Catppuccin Mocha sRGB, shared by the board, CLI, and Reminders lists.
public enum FinderTagColour: Sendable {
    /// sRGB components in 0…1.
    public struct RGB: Sendable, Equatable {
        public let red: Double
        public let green: Double
        public let blue: Double

        public init(red: Double, green: Double, blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }
    }

    /// Colour for a Finder tag index, or `nil` when the index is not 1…7.
    public static func sRGB(for index: Int) -> RGB? {
        switch index {
        case 1: return RGB(red: 108 / 255, green: 112 / 255, blue: 134 / 255) // Overlay0
        case 2: return RGB(red: 166 / 255, green: 227 / 255, blue: 161 / 255) // Green
        case 3: return RGB(red: 203 / 255, green: 166 / 255, blue: 247 / 255) // Mauve
        case 4: return RGB(red: 137 / 255, green: 180 / 255, blue: 250 / 255) // Blue
        case 5: return RGB(red: 249 / 255, green: 226 / 255, blue: 175 / 255) // Yellow
        case 6: return RGB(red: 250 / 255, green: 179 / 255, blue: 135 / 255) // Peach
        case 7: return RGB(red: 243 / 255, green: 139 / 255, blue: 168 / 255) // Red
        default: return nil
        }
    }

    /// Truecolour ANSI foreground escape for a Finder tag index.
    public static func ansiTrueColour(for index: Int) -> String? {
        guard let rgb = sRGB(for: index) else { return nil }
        let r = Int((rgb.red * 255).rounded())
        let g = Int((rgb.green * 255).rounded())
        let b = Int((rgb.blue * 255).rounded())
        return "\u{1B}[38;2;\(r);\(g);\(b)m"
    }

    #if canImport(CoreGraphics)
    /// EventKit / AppKit colour for a reminder list or calendar, or `nil` when the index is unknown.
    public static func cgColor(for index: Int) -> CGColor? {
        guard let rgb = sRGB(for: index) else { return nil }
        return CGColor(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
    }
    #endif
}

extension BoardConfig {
    /// Finder tag colour index (1–7) for a kanban column name, if configured.
    public func colourIndex(forColumn name: String) -> Int? {
        let lower = name.lowercased()
        return columns.first { $0.name.lowercased() == lower }?.colour
    }
}
