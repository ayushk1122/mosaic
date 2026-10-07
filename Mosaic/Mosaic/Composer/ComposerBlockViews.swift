import SwiftUI

struct ComposerBlockRow: View {
    let block: ComposerBlock
    let isSelected: Bool
    let mediaURL: URL?
    var opensPursuitInParentStack: Bool

    var body: some View {
        Group {
            switch block.kind {
            case .text, .heading:
                textBlock
            case .media:
                mediaBlock
            case .carousel:
                Label("Carousel", systemImage: "rectangle.stack")
                    .font(.headline)
            case .link:
                linkBlock
            case .pursuit:
                pursuitBlock
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isSelected ? MosaicBrand.inkBlack : Color.clear, lineWidth: 2)
        }
        .accessibilityIdentifier("composer.block.\(block.id.rawValue)")
    }

    private var textBlock: some View {
        Text(block.text)
            .font(block.style.size.font(isHeading: block.kind == .heading))
            .foregroundStyle(block.style.color.color)
            .multilineTextAlignment(block.style.alignment.alignment)
            .frame(maxWidth: .infinity, alignment: block.style.alignment == .center ? .center : .leading)
    }

    @ViewBuilder
    private var mediaBlock: some View {
        if let mediaURL, let uiImage = UIImage(contentsOfFile: mediaURL.path) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            VStack(spacing: 8) {
                Image(systemName: "photo")
                    .font(.title2)
                Text("Add a photo from the editor")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
        }
    }

    private var linkBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(block.text, systemImage: "link")
                .font(.headline)
            if let url = block.linkURL, !url.isEmpty {
                Text(url)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var pursuitBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(block.text, systemImage: "square.grid.2x2")
                .font(.title3.weight(.semibold))
            if opensPursuitInParentStack, let pursuitID = block.pursuitID {
                NavigationLink(value: pursuitID) {
                    Text("Open Pursuit")
                }
                .buttonStyle(.borderedProminent)
                .tint(MosaicBrand.inkBlack)
                .accessibilityIdentifier("composer.pursuit.open.\(pursuitID.rawValue)")
            }
        }
    }
}
