import SwiftUI

enum UITheme: String, CaseIterable, Identifiable, Sendable, Codable {
    case midnight
    case paper
    case forest

    var id: String { rawValue }

    func title(_ language: AppLanguage) -> String {
        switch self {
        case .midnight:
            return language == .japanese ? "ミッドナイト" : "Midnight"
        case .paper:
            return language == .japanese ? "ペーパー" : "Paper"
        case .forest:
            return language == .japanese ? "フォレスト" : "Forest"
        }
    }

    var appearance: UIThemeAppearance {
        switch self {
        case .midnight:
            return UIThemeAppearance(
                backgroundTop: Color(red: 0.08, green: 0.08, blue: 0.12),
                backgroundBottom: Color(red: 0.12, green: 0.10, blue: 0.16),
                accentStart: Color(red: 0.45, green: 0.24, blue: 0.90),
                accentEnd: Color(red: 0.13, green: 0.47, blue: 0.95),
                accent: Color(red: 0.24, green: 0.56, blue: 0.98),
                accentSoft: Color(red: 0.24, green: 0.56, blue: 0.98).opacity(0.15),
                panelFill: Color.white.opacity(0.03),
                elevatedFill: Color.white.opacity(0.08),
                divider: Color.white.opacity(0.10),
                selectionFill: Color(red: 0.24, green: 0.56, blue: 0.98).opacity(0.16),
                selectionStroke: Color(red: 0.24, green: 0.56, blue: 0.98).opacity(0.42),
                previewSurface: Color(red: 0.06, green: 0.06, blue: 0.08),
                dropTargetStroke: Color.white.opacity(0.15),
                dropTargetFill: Color.white.opacity(0.03),
                secondaryText: Color.white.opacity(0.5),
                tertiaryText: Color.white.opacity(0.35)
            )
        case .paper:
            return UIThemeAppearance(
                backgroundTop: Color(red: 0.18, green: 0.14, blue: 0.11),
                backgroundBottom: Color(red: 0.28, green: 0.20, blue: 0.15),
                accentStart: Color(red: 0.89, green: 0.55, blue: 0.28),
                accentEnd: Color(red: 0.73, green: 0.36, blue: 0.16),
                accent: Color(red: 0.92, green: 0.62, blue: 0.33),
                accentSoft: Color(red: 0.92, green: 0.62, blue: 0.33).opacity(0.14),
                panelFill: Color.white.opacity(0.05),
                elevatedFill: Color.white.opacity(0.09),
                divider: Color.white.opacity(0.10),
                selectionFill: Color(red: 0.92, green: 0.62, blue: 0.33).opacity(0.16),
                selectionStroke: Color(red: 0.92, green: 0.62, blue: 0.33).opacity(0.36),
                previewSurface: Color(red: 0.13, green: 0.10, blue: 0.08),
                dropTargetStroke: Color.white.opacity(0.16),
                dropTargetFill: Color.white.opacity(0.03),
                secondaryText: Color.white.opacity(0.5),
                tertiaryText: Color.white.opacity(0.35)
            )
        case .forest:
            return UIThemeAppearance(
                backgroundTop: Color(red: 0.08, green: 0.15, blue: 0.12),
                backgroundBottom: Color(red: 0.12, green: 0.22, blue: 0.16),
                accentStart: Color(red: 0.19, green: 0.60, blue: 0.42),
                accentEnd: Color(red: 0.08, green: 0.40, blue: 0.29),
                accent: Color(red: 0.21, green: 0.70, blue: 0.50),
                accentSoft: Color(red: 0.21, green: 0.70, blue: 0.50).opacity(0.14),
                panelFill: Color.white.opacity(0.04),
                elevatedFill: Color.white.opacity(0.08),
                divider: Color.white.opacity(0.09),
                selectionFill: Color(red: 0.21, green: 0.70, blue: 0.50).opacity(0.15),
                selectionStroke: Color(red: 0.21, green: 0.70, blue: 0.50).opacity(0.35),
                previewSurface: Color(red: 0.05, green: 0.10, blue: 0.08),
                dropTargetStroke: Color.white.opacity(0.16),
                dropTargetFill: Color.white.opacity(0.03),
                secondaryText: Color.white.opacity(0.5),
                tertiaryText: Color.white.opacity(0.35)
            )
        }
    }
}

struct UIThemeAppearance {
    let backgroundTop: Color
    let backgroundBottom: Color
    let accentStart: Color
    let accentEnd: Color
    let accent: Color
    let accentSoft: Color
    let panelFill: Color
    let elevatedFill: Color
    let divider: Color
    let selectionFill: Color
    let selectionStroke: Color
    let previewSurface: Color
    let dropTargetStroke: Color
    let dropTargetFill: Color
    let secondaryText: Color
    let tertiaryText: Color
}
