import SwiftUI
import UIKit

enum ComposerBannerMetrics {
    static let minimumHeight: CGFloat = 96
    static let maximumHeight: CGFloat = 420
    static let defaultHeight: Double = 196

    static func clamped(_ height: CGFloat) -> CGFloat {
        min(max(height, minimumHeight), maximumHeight)
    }

    /// Dragging the bottom edge down makes the banner taller.
    static func resized(base: CGFloat, translation: CGFloat) -> CGFloat {
        clamped(base + translation)
    }
}

struct ComposerBannerBlock: View {
    @Environment(\.composerMediaVersions) private var mediaVersions

    @Binding var block: ComposerBlock
    let mediaURL: URL?
    var isSelected: Bool
    var isEditing: Bool
    var isViewing: Bool
    var focusBlockID: FocusState<ComposerBlockID?>.Binding
    var onSelect: () -> Void
    var onBeginEditing: () -> Void
    var onCommit: () -> Void
    var onReplaceMedia: () -> Void
    var onDelete: () -> Void

    @Environment(\.composerViewportWidth) private var viewportWidth
    @Environment(\.composerPaperPage) private var onPaper

    private var readingColor: Color {
        block.style.readingColor(onPaper: onPaper)
    }
    @State private var image: UIImage?
    @State private var panOrigin: CGSize?
    @State private var heightOrigin: CGFloat?
    @GestureState private var livePinch: CGFloat = 1

    private var height: CGFloat {
        ComposerBannerMetrics.clamped(CGFloat(block.bannerHeight))
    }

    private var showsChrome: Bool {
        isSelected && !isViewing
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            mediaLayer
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.42),
                    .init(color: MosaicBrand.inkBlack.opacity(0.35), location: 0.72),
                    .init(color: MosaicBrand.inkBlack, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)
            titleLayer
                .padding(.horizontal, 20)
                .padding(.bottom, 22)
            if showsChrome {
                chrome
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipped()
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            if showsChrome {
                heightHandle
            }
        }
        .onTapGesture {
            guard !isViewing, !isEditing else { return }
            onSelect()
        }
        .task(id: ComposerMediaLoadKey(mediaURL, versions: mediaVersions)) {
            image = mediaURL.flatMap { UIImage(contentsOfFile: $0.path) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("composer.banner.\(block.id.rawValue)")
    }

    @ViewBuilder
    private var mediaLayer: some View {
        let frame = CGSize(width: max(viewportWidth, 1), height: height)
        let zoom = CGFloat(min(max(block.mediaZoom, 1), 4)) * livePinch
        let contentAspect = imageAspect
        let filled = MediaFraming.fillSize(contentAspect: contentAspect, in: frame)
        let pan = MediaFraming.clampedPan(
            CGSize(width: block.mediaPanX * frame.width, height: block.mediaPanY * frame.height),
            limits: MediaFraming.panLimits(contentAspect: contentAspect, frame: frame, zoom: max(zoom, 1))
        )
        Color.clear
            .frame(width: frame.width, height: frame.height)
            .overlay {
                Group {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else if let mediaURL, Self.isVideo(mediaURL) {
                        ComposerInlineVideo(url: mediaURL, isPaused: true, fillsFrame: true)
                            .allowsHitTesting(false)
                    } else {
                        Color.white.opacity(0.08)
                    }
                }
                .frame(width: filled.width, height: filled.height)
                .scaleEffect(zoom)
                .offset(pan)
            }
            .clipped()
            .contentShape(Rectangle())
            .highPriorityGesture(SimultaneousGesture(imagePinch, panGesture))
    }

    private var titleLayer: some View {
        let trimmed = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return Group {
            if isEditing, !isViewing {
                TextField("Add text", text: $block.text, axis: .vertical)
                    .font(block.style.displayFont())
                    .foregroundStyle(readingColor)
                    .lineLimit(1...3)
                    .focused(focusBlockID, equals: block.id)
                    .submitLabel(.done)
                    .onSubmit(onCommit)
            } else if !trimmed.isEmpty {
                Text(trimmed)
                    .font(block.style.displayFont())
                    .foregroundStyle(readingColor)
                    .lineLimit(3)
                    .onTapGesture {
                        guard !isViewing else { return }
                        onBeginEditing()
                    }
            } else if showsChrome {
                Text("Add text")
                    .font(block.style.displayFont())
                    .foregroundStyle(readingColor.opacity(0.55))
                    .onTapGesture(perform: onBeginEditing)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var chrome: some View {
        VStack {
            HStack {
                Spacer()
                bannerButton("photo", label: "Edit banner photo", action: onReplaceMedia)
                bannerButton("trash", label: "Delete banner", action: onDelete)
            }
            Spacer()
        }
        .padding(12)
    }

    private var heightHandle: some View {
        Capsule()
            .fill(Color.white.opacity(0.92))
            .frame(width: 44, height: 5)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let origin = heightOrigin ?? height
                        if heightOrigin == nil {
                            heightOrigin = height
                        }
                        block.bannerHeight = Double(ComposerBannerMetrics.resized(base: origin, translation: value.translation.height))
                    }
                    .onEnded { _ in
                        heightOrigin = nil
                    }
            )
            .accessibilityLabel("Banner height")
            .accessibilityAddTraits(.isButton)
    }

    private func bannerButton(_ systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Image(systemName: systemName)
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 32, height: 32)
            .background(Color.black.opacity(0.45), in: Circle())
            .contentShape(Circle())
            .highPriorityGesture(TapGesture().onEnded(action))
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
    }

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard showsChrome, !isEditing else { return }
                let frame = CGSize(width: max(viewportWidth, 1), height: height)
                let origin = panOrigin ?? CGSize(width: block.mediaPanX * frame.width, height: block.mediaPanY * frame.height)
                if panOrigin == nil {
                    panOrigin = origin
                }
                let zoom = CGFloat(min(max(block.mediaZoom, 1), 4))
                let proposed = CGSize(width: origin.width + value.translation.width, height: origin.height + value.translation.height)
                let clamped = MediaFraming.clampedPan(
                    proposed,
                    limits: MediaFraming.panLimits(contentAspect: imageAspect, frame: frame, zoom: zoom)
                )
                block.mediaPanX = frame.width > 0 ? Double(clamped.width / frame.width) : 0
                block.mediaPanY = frame.height > 0 ? Double(clamped.height / frame.height) : 0
            }
            .onEnded { _ in
                panOrigin = nil
            }
    }

    private var imagePinch: some Gesture {
        MagnificationGesture()
            .updating($livePinch) { value, state, _ in
                guard showsChrome, !isEditing else { return }
                state = value
            }
            .onEnded { value in
                guard showsChrome, !isEditing else { return }
                let next = min(max(block.mediaZoom * Double(value), 1), 4)
                block.mediaZoom = next
                let frame = CGSize(width: max(viewportWidth, 1), height: height)
                let clamped = MediaFraming.clampedPan(
                    CGSize(width: block.mediaPanX * frame.width, height: block.mediaPanY * frame.height),
                    limits: MediaFraming.panLimits(contentAspect: imageAspect, frame: frame, zoom: CGFloat(next))
                )
                block.mediaPanX = frame.width > 0 ? Double(clamped.width / frame.width) : 0
                block.mediaPanY = frame.height > 0 ? Double(clamped.height / frame.height) : 0
            }
    }

    private var imageAspect: CGFloat {
        guard let image, image.size.height > 0 else { return 16.0 / 9.0 }
        return image.size.width / image.size.height
    }

    private static func isVideo(_ url: URL) -> Bool {
        ["mov", "mp4", "m4v"].contains(url.pathExtension.lowercased())
    }
}
