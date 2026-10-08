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
        displayFont(at: fontSize * scale)
    }

    func displayFont(at size: CGFloat) -> Font {
        if let fontFamilyName {
            return ComposerInstalledFont.font(
                family: fontFamilyName,
                size: size,
                bold: isBold,
                italic: isItalic
            )
        }
        return fontChoice.font(size: size, bold: isBold, italic: isItalic)
    }
}

enum ComposerInstalledFont {
    static let familyNames: [String] = UIFont.familyNames.sorted()

    static func font(family: String, size: CGFloat, bold: Bool = false, italic: Bool = false) -> Font {
        if bold || italic {
            var traits = UIFontDescriptor.SymbolicTraits()
            if bold { traits.insert(.traitBold) }
            if italic { traits.insert(.traitItalic) }
            let base = UIFontDescriptor(fontAttributes: [.family: family])
            if let described = base.withSymbolicTraits(traits) {
                return Font(UIFont(descriptor: described, size: size))
            }
        }
        let names = UIFont.fontNames(forFamilyName: family)
        let preferred = names.first { $0.localizedCaseInsensitiveContains("Regular") }
            ?? names.first
            ?? family
        return .custom(preferred, size: size)
    }
}

extension ComposerFontChoice {
    func font(size: CGFloat, bold: Bool = false, italic: Bool = false) -> Font {
        switch self {
        case .system:
            Self.systemFont(size: size, design: .default, bold: bold, italic: italic)
        case .rounded:
            Self.systemFont(size: size, design: .rounded, bold: bold, italic: italic)
        case .serif:
            Self.systemFont(size: size, design: .serif, bold: bold, italic: italic)
        case .mono:
            Self.systemFont(size: size, design: .monospaced, bold: bold, italic: italic)
        case .avenir:
            ComposerInstalledFont.font(family: "Avenir Next", size: size, bold: bold, italic: italic)
        case .georgia:
            ComposerInstalledFont.font(family: "Georgia", size: size, bold: bold, italic: italic)
        case .futura:
            ComposerInstalledFont.font(family: "Futura", size: size, bold: bold, italic: italic)
        }
    }

    private static func systemFont(size: CGFloat, design: Font.Design, bold: Bool, italic: Bool) -> Font {
        var font = Font.system(size: size, weight: bold ? .bold : .regular, design: design)
        if italic {
            font = font.italic()
        }
        return font
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
