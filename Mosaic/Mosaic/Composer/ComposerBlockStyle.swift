import SwiftUI
import UIKit

extension TextBlockColor {
    var color: Color {
        switch self {
        case .canvas: Color.white
        case .ink: MosaicBrand.inkBlack
        case .charcoal: Color(red: 0.22, green: 0.22, blue: 0.24)
        case .forest: Color(red: 0.12, green: 0.38, blue: 0.28)
        case .clay: Color(red: 0.62, green: 0.34, blue: 0.22)
        }
    }
}

extension TextBlockStyle {
    var displayColor: Color {
        if let customColor {
            return Color(
                red: customColor.red,
                green: customColor.green,
                blue: customColor.blue,
                opacity: customColor.opacity
            )
        }
        return color.color
    }

    var fontLabel: String {
        fontFamilyName ?? fontChoice.label
    }

    func displayFont() -> Font {
        let size = fontSize * scale
        if let fontFamilyName {
            return ComposerInstalledFont.font(family: fontFamilyName, size: size)
        }
        return fontChoice.font(size: size)
    }
}

enum ComposerInstalledFont {
    static var familyNames: [String] {
        UIFont.familyNames.sorted()
    }

    static func font(family: String, size: CGFloat) -> Font {
        let names = UIFont.fontNames(forFamilyName: family)
        let preferred = names.first { $0.localizedCaseInsensitiveContains("Regular") }
            ?? names.first
            ?? family
        return .custom(preferred, size: size)
    }
}

extension ComposerFontChoice {
    func font(size: CGFloat) -> Font {
        switch self {
        case .system:
            .system(size: size)
        case .rounded:
            .system(size: size, weight: .regular, design: .rounded)
        case .serif:
            .system(size: size, weight: .regular, design: .serif)
        case .mono:
            .system(size: size, weight: .regular, design: .monospaced)
        case .avenir:
            .custom("Avenir Next", size: size)
        case .georgia:
            .custom("Georgia", size: size)
        case .futura:
            .custom("Futura", size: size)
        }
    }
}

extension TextBlockSize {
    func font(isHeading: Bool) -> Font {
        switch self {
        case .body:
            isHeading ? .title3.weight(.semibold) : .body
        case .large:
            isHeading ? .title2.weight(.semibold) : .title3
        case .title:
            isHeading ? .largeTitle.weight(.medium) : .title2.weight(.semibold)
        }
    }
}

extension TextAlignmentOption {
    var alignment: TextAlignment {
        switch self {
        case .leading: .leading
        case .center: .center
        }
    }

    var horizontalAlignment: HorizontalAlignment {
        switch self {
        case .leading: .leading
        case .center: .center
        }
    }

    var frameAlignment: Alignment {
        switch self {
        case .leading: .leading
        case .center: .center
        }
    }
}
