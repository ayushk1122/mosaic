import SwiftUI

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
