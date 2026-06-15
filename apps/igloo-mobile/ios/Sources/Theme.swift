// Igloo Design Tokens - derived from igloo-paper design-system/tokens/
// This file is generated from tokens.css / colors.json / typography.json
// and should be re-generated when tokens change. It is NOT imported from
// repos/igloo-paper directly (reference-only, one-way codegen).

import SwiftUI

// MARK: - Colors

enum IglooColors {
    // Background
    static let Gray950 = Color(hex: "030712")
    static let Gray900 = Color(hex: "111827")
    static let Gray900Translucent = Color(hex: "111827", alpha: 0.40)
    static let Slate900Translucent = Color(hex: "0F172A", alpha: 0.60)
    static let Slate900StrongTranslucent = Color(hex: "0F172A", alpha: 0.80)

    // Blue Scale - Primary
    static let Blue100 = Color(hex: "DBEAFE")
    static let Blue200 = Color(hex: "BFDBFE")
    static let Blue300 = Color(hex: "93C5FD")
    static let Blue400 = Color(hex: "60A5FA")
    static let Blue600 = Color(hex: "2563EB")
    static let Blue700 = Color(hex: "1D4ED8")
    static let Blue900 = Color(hex: "1E3A8A")

    // Semantic
    static let Green600 = Color(hex: "16A34A")
    static let Red400 = Color(hex: "F87171")
    static let Red600 = Color(hex: "DC2626")
    static let Amber400 = Color(hex: "FBBF24")
    static let Orange400 = Color(hex: "FB923C")
    static let Purple400 = Color(hex: "C084FC")
    static let Red900Translucent = Color(hex: "7F1D1D", alpha: 0.30)
    static let Yellow900Translucent = Color(hex: "713F12", alpha: 0.30)

    // Interface Text
    static let Slate200 = Color(hex: "E2E8F0")
    static let Slate300 = Color(hex: "CBD5E1")
    static let Slate400 = Color(hex: "94A3B8")
    static let Slate500 = Color(hex: "64748B")

    // Interface Borders & Overlays
    static let Blue900FocusBorder = Color(hex: "1E3A8A", alpha: 0.30)
    static let Blue900PanelBorder = Color(hex: "1E3A8A", alpha: 0.20)
    static let Slate400MutedBorder = Color(hex: "94A3B8", alpha: 0.20)
    static let Red500DestructiveBg = Color(hex: "EF4444", alpha: 0.06)
    static let Red500DestructiveBorder = Color(hex: "EF4444", alpha: 0.30)

    // Status
    static let StatusDefault = Color(hex: "6B7280")
    static let StatusSuccess = Color(hex: "22C55E")
    static let StatusError = Color(hex: "EF4444")
    static let StatusWarning = Color(hex: "EAB308")
    static let StatusInfo = Color(hex: "3B82F6")

    // Compatibility aliases for restored SwiftUI views that used lower-camel tokens.
    static let gray950 = Gray950
    static let slate900StrongTranslucent = Slate900StrongTranslucent
    static let blue400 = Blue400
    static let blue900PanelBorder = Blue900PanelBorder
    static let green600 = Green600
    static let slate200 = Slate200
    static let slate300 = Slate300
    static let slate400 = Slate400
    static let slate500 = Slate500
    static let statusDefault = StatusDefault
}

// MARK: - Typography

enum IglooTypography {
    // H1 Heading - Share Tech Mono 36px regular
    static let H1Font = Font.custom("Share Tech Mono", size: 36)
    static let H1LineHeight: CGFloat = 44
    static let H1Tracking: CGFloat = -0.01

    // H2 Section Header - Share Tech Mono 24px regular
    static let H2Font = Font.custom("Share Tech Mono", size: 24)
    static let H2LineHeight: CGFloat = 30

    // H3 Card Title - Share Tech Mono 20px regular
    static let H3Font = Font.custom("Share Tech Mono", size: 20)
    static let H3LineHeight: CGFloat = 24

    // Body text - Inter 14px regular
    static let BodyFont = Font.custom("Inter", size: 14)
    static let BodyLineHeight: CGFloat = 18

    // Small - Inter 12px regular
    static let SmallFont = Font.custom("Inter", size: 12)
    static let SmallLineHeight: CGFloat = 16

    // Value data - Share Tech Mono 14px regular
    static let ValueDataFont = Font.custom("Share Tech Mono", size: 14)
    static let ValueDataLineHeight: CGFloat = 18

    // Mono labels - Inter 12px regular (medium weight for slight emphasis)
    static let MonoLabelFont = Font.custom("Inter", size: 12).weight(.medium)

    // Compatibility aliases for restored SwiftUI views that used lower-camel tokens.
    static let h2Font = H2Font
    static let h3Font = H3Font
    static let bodyFont = BodyFont
}

// MARK: - Spacing & Radii

enum IglooSpacing {
    static let Xs: CGFloat = 4
    static let Sm: CGFloat = 8
    static let Md: CGFloat = 16
    static let Lg: CGFloat = 24
    static let Xl: CGFloat = 32
    static let Xxl: CGFloat = 48

    // Compatibility aliases for restored SwiftUI views that used lower-camel tokens.
    static let xs = Xs
    static let sm = Sm
    static let md = Md
    static let lg = Lg
}

enum IglooRadii {
    static let Sm: CGFloat = 8
    static let Md: CGFloat = 12
    static let Lg: CGFloat = 16
    static let Xl: CGFloat = 18
    static let Full: CGFloat = 9999

    // Compatibility aliases for restored SwiftUI views that used lower-camel tokens.
    static let md = Md
    static let lg = Lg
}

// MARK: - Color Extension

extension Color {
    init(hex: String, alpha: Double = 1.0) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 6:
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: alpha
        )
    }
}

// MARK: - Theme Environment

struct IglooTheme {
    let background = IglooColors.Gray950
    let surfacePanel = IglooColors.Slate900StrongTranslucent
    let surfaceCard = IglooColors.Gray900Translucent
    let border = IglooColors.Blue900PanelBorder
    let borderFocused = IglooColors.Blue900FocusBorder
    let primary = IglooColors.Blue600
    let primaryAccent = IglooColors.Blue400
    let textPrimary = IglooColors.Slate200
    let textSecondary = IglooColors.Slate400
    let textMuted = IglooColors.Slate500
}

extension EnvironmentValues {
    var iglooTheme: IglooTheme {
        IglooTheme()
    }
}
