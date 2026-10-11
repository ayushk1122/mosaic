import SwiftUI

enum ScrapbookMetrics {
    /// Width of the spiral column on the open journal and on the cover.
    static let spiral: CGFloat = 36
}

enum ScrapbookColors {
    static let cover = Color(red: 0.965, green: 0.949, blue: 0.902)
    static let paper = Color(red: 0.976, green: 0.957, blue: 0.914)
    static let paperEdge = Color(red: 0.91, green: 0.87, blue: 0.78)
    static let spine = Color(red: 0.22, green: 0.18, blue: 0.15)
    static let edge = Color(red: 0.90, green: 0.87, blue: 0.80)
    static let ink = Color(red: 0.16, green: 0.13, blue: 0.10)
}

struct ComposerScrapbookCover: View {
    var title: String
    var scale: CGFloat
    var isSelected: Bool

    private var width: CGFloat { 148 * scale }
    private var height: CGFloat { 200 * scale }
    /// Same spiral column as the open journal, scaled with the cover.
    private var spineWidth: CGFloat { ScrapbookMetrics.spiral * scale }

    private var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Scrapbook" : trimmed
    }

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 8 * scale, style: .continuous)
                .fill(ScrapbookColors.cover)
            RoundedRectangle(cornerRadius: 8 * scale, style: .continuous)
                .stroke(ScrapbookColors.ink.opacity(0.16), lineWidth: 1)
            ScrapbookColors.paperEdge
                .frame(width: spineWidth, height: height)
            SpiralBinding(pageHeight: height, columnWidth: spineWidth)
                .frame(width: spineWidth, height: height)
                .allowsHitTesting(false)
            Text(displayTitle)
                .font(.system(size: 20 * scale, weight: .semibold, design: .serif))
                .foregroundStyle(ScrapbookColors.ink)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .padding(.leading, spineWidth + 8 * scale)
                .padding(.trailing, 12 * scale)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: width, height: height)
        .shadow(color: .black.opacity(0.28), radius: 10 * scale, y: 6 * scale)
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 8 * scale, style: .continuous)
                    .stroke(Color.white.opacity(0.9), lineWidth: 1.5)
            }
        }
        .accessibilityLabel(displayTitle)
        .accessibilityIdentifier("scrapbook.cover")
    }
}

struct ScrapbookBookView: View {
    let parentDocumentID: ComposerDocumentID?
    let blockID: ComposerBlockID
    var onClose: () -> Void

    @Environment(ComposerStore.self) private var store
    @Environment(MosaicChrome.self) private var chrome
    @State private var index = 0
    @State private var drag: CGFloat = 0
    @State private var settling = false
    @State private var mediaObscured = false

    private var block: ComposerBlock? {
        store.block(with: blockID, in: parentDocumentID)
    }

    private var pageIDs: [ComposerDocumentID] {
        block?.scrapbookPageIDs ?? []
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.94)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)
            VStack(spacing: 14) {
                header
                book
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 16)
        }
        .accessibilityIdentifier("scrapbook.book")
        .onAppear(perform: restoreIndex)
        .onChange(of: pageIDs.count) { _, count in
            guard !settling else { return }
            index = min(index, max(count - 1, 0))
        }
        .onPreferenceChange(ComposerMediaObscuredKey.self) { mediaObscured = $0 }
    }

    private func restoreIndex() {
        guard !pageIDs.isEmpty else { return }
        index = min(max(block?.scrapbookIndex ?? 0, 0), pageIDs.count - 1)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.14), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close scrapbook")

            titleField
            Spacer(minLength: 0)
            if !chrome.isViewing {
                pageButtons
            }
        }
    }

    @ViewBuilder
    private var titleField: some View {
        let title = block?.text ?? "Scrapbook"
        if chrome.isViewing {
            Text(title.isEmpty ? "Scrapbook" : title)
                .font(.system(.headline, design: .serif))
                .foregroundStyle(.white)
                .lineLimit(1)
        } else {
            TextField(
                "Scrapbook",
                text: Binding(
                    get: { block?.text ?? "" },
                    set: { newValue in
                        guard var current = store.block(with: blockID, in: parentDocumentID) else { return }
                        current.text = newValue
                        store.updateBlock(current, in: parentDocumentID)
                    }
                )
            )
            .font(.system(.headline, design: .serif))
            .foregroundStyle(.white)
            .lineLimit(1)
            .accessibilityLabel("Scrapbook title")
        }
    }

    private var pageButtons: some View {
        HStack(spacing: 8) {
            if pageIDs.count > 1 {
                Button {
                    guard let next = store.removeScrapbookPage(at: index, on: blockID, in: parentDocumentID) else { return }
                    index = next
                } label: {
                    Image(systemName: "minus")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.14), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove page")
            }
            Button {
                guard let created = store.insertScrapbookPage(after: index, on: blockID, in: parentDocumentID) else { return }
                index = created
            } label: {
                Image(systemName: "plus")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.14), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(pageIDs.count >= 30)
            .accessibilityLabel("Add page")
        }
    }

    private var livePageIDs: [ComposerDocumentID] {
        store.block(with: blockID, in: parentDocumentID)?.scrapbookPageIDs ?? pageIDs
    }

    private var book: some View {
        GeometryReader { proxy in
            let spiral = ScrapbookMetrics.spiral
            let pageWidth = max(proxy.size.width - spiral, 1)
            let pageHeight = proxy.size.height
            ZStack(alignment: .topLeading) {
                notebook(pageWidth: pageWidth, pageHeight: pageHeight, spiral: spiral)
                if !settling {
                    HStack(spacing: 0) {
                        ScrapbookTurnSurface(
                            onChanged: { followTurn($0, pageWidth: pageWidth) },
                            onEnded: { translation, predicted in
                                finishTurn(translation: translation, predicted: predicted, pageWidth: pageWidth)
                            }
                        )
                        .frame(width: spiral + 44)
                        Spacer(minLength: 0)
                            .allowsHitTesting(false)
                        VStack(spacing: 0) {
                            ScrapbookTurnSurface(
                                onChanged: { followTurn($0, pageWidth: pageWidth) },
                                onEnded: { translation, predicted in
                                    finishTurn(translation: translation, predicted: predicted, pageWidth: pageWidth)
                                }
                            )
                            Color.clear
                                .frame(height: 108)
                                .allowsHitTesting(false)
                        }
                        .frame(width: 96)
                    }
                    .frame(width: proxy.size.width, height: pageHeight)
                    pageEdgeHint
                }
                SpiralBinding(pageHeight: pageHeight, columnWidth: spiral)
                    .frame(width: spiral, height: pageHeight)
                    .allowsHitTesting(false)
                    .overlay {
                        if mediaObscured {
                            Color.black.opacity(0.94)
                        }
                    }
            }
            .background(ScrapbookColors.paperEdge)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.35), radius: 18, y: 10)
        }
    }

    private func notebook(pageWidth: CGFloat, pageHeight: CGFloat, spiral: CGFloat) -> some View {
        let turningBack = drag > 0
        let restingID = pageIDs[safe: index]
        let underneathID = turningBack ? pageIDs[safe: index] : pageIDs[safe: index + 1]
        let movingID = turningBack ? pageIDs[safe: index - 1] : restingID
        let movingOffset = turningBack ? drag - pageWidth : drag
        return HStack(spacing: 0) {
            Color.clear.frame(width: spiral)
            ZStack {
                if abs(drag) > 0.5 {
                    sheet(underneathID, number: (turningBack ? index : index + 1) + 1)
                    if let movingID {
                        sheet(movingID, number: (turningBack ? index - 1 : index) + 1)
                            .offset(x: movingOffset)
                            .shadow(color: .black.opacity(0.18), radius: 10, x: -6, y: 2)
                    }
                } else {
                    sheet(restingID, number: index + 1)
                }
            }
            .frame(width: pageWidth, height: pageHeight)
            .clipped()
        }
        .allowsHitTesting(abs(drag) < 1)
    }

    private func sheet(_ pageID: ComposerDocumentID?, number: Int) -> some View {
        ZStack(alignment: .topTrailing) {
            ScrapbookColors.paper
            if let pageID {
                MosaicComposerView(documentID: pageID, isBookPage: true)
                    .id(pageID)
            }
            if number > 0 {
                Text("\(number)")
                    .font(.system(size: 12, weight: .medium, design: .serif))
                    .foregroundStyle(ScrapbookColors.ink.opacity(0.4))
                    .padding(.top, 10)
                    .padding(.trailing, 14)
                    .allowsHitTesting(false)
            }
        }
        .clipped()
    }

    private var pageEdgeHint: some View {
        PageCornerHint()
            .padding(.top, 8)
            .padding(.trailing, 8)
            .opacity(index < livePageIDs.count - 1 && abs(drag) < 1 ? 1 : 0)
            .allowsHitTesting(false)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    }

    private func followTurn(_ translation: CGFloat, pageWidth: CGFloat) {
        guard !settling else { return }
        let count = livePageIDs.count
        if translation < 0 {
            let limit = index < count - 1 ? pageWidth : pageWidth * 0.12
            drag = max(translation, -limit)
        } else {
            let limit = index > 0 ? pageWidth : pageWidth * 0.12
            drag = min(translation, limit)
        }
    }

    private func finishTurn(translation: CGFloat, predicted: CGFloat, pageWidth: CGFloat) {
        guard !settling else { return }
        let count = max(livePageIDs.count, 1)
        let forward = translation < 0 || (translation == 0 && predicted < 0)
        let next = min(max(index + (forward ? 1 : -1), 0), count - 1)
        let traveled = abs(drag)
        let flung = abs(predicted) > 90
        guard next != index, traveled > 48 || (flung && traveled > 20) else {
            withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) {
                drag = 0
            }
            return
        }
        settling = true
        store.rememberScrapbookPage(next, on: blockID, in: parentDocumentID)
        withAnimation(.easeInOut(duration: 0.42)) {
            drag = forward ? -pageWidth : pageWidth
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(440))
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                index = next
                drag = 0
            }
            settling = false
            UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.5)
        }
    }
}

private struct SpiralBinding: View {
    var pageHeight: CGFloat
    var columnWidth: CGFloat = ScrapbookMetrics.spiral
    var ring: Color = Color(white: 0.78)

    private var scale: CGFloat { max(columnWidth / ScrapbookMetrics.spiral, 0.2) }

    var body: some View {
        let count = max(Int(pageHeight / (28 * scale)), 5)
        VStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { _ in
                SpiralRing(scale: scale, ring: ring)
                    .frame(maxHeight: .infinity)
            }
        }
        .padding(.vertical, 8 * scale)
        .frame(width: columnWidth, height: pageHeight)
    }
}

struct ComposerMediaObscuredKey: PreferenceKey {
    static var defaultValue = false

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

private struct SpiralRing: View {
    var scale: CGFloat = 1
    var ring: Color = Color(white: 0.78)

    var body: some View {
        ZStack {
            Capsule()
                .fill(Color.black.opacity(0.28))
                .frame(width: 8 * scale, height: 8 * scale)
                .offset(x: 8 * scale)
            Capsule()
                .stroke(
                    LinearGradient(
                        colors: [
                            ring.opacity(0.95),
                            ring.opacity(0.45),
                            ring.opacity(0.8)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: max(1.5, 2.5 * scale)
                )
                .frame(width: 26 * scale, height: 16 * scale)
                .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
        }
        .frame(width: ScrapbookMetrics.spiral * scale, height: 22 * scale)
    }
}

/// Horizontal drags anywhere on the page turn it. Vertical drags still scroll the page.
private struct ScrapbookTurnSurface: UIViewRepresentable {
    var onChanged: (CGFloat) -> Void
    var onEnded: (_ translation: CGFloat, _ predicted: CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> ScrapbookTurnView {
        let view = ScrapbookTurnView()
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ uiView: ScrapbookTurnView, context: Context) {
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
        uiView.coordinator = context.coordinator
    }

    final class Coordinator {
        var onChanged: (CGFloat) -> Void = { _ in }
        var onEnded: (CGFloat, CGFloat) -> Void = { _, _ in }
    }
}

private final class ScrapbookTurnView: UIView, UIGestureRecognizerDelegate {
    weak var coordinator: ScrapbookTurnSurface.Coordinator?
    private var lockedScroll: UIScrollView?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
        pan.delegate = self
        pan.cancelsTouchesInView = false
        addGestureRecognizer(pan)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
        let velocity = pan.velocity(in: self)
        let location = pan.location(in: self)
        if location.y > bounds.height - 108 { return false }
        return abs(velocity.x) > abs(velocity.y) * 1.1 && abs(velocity.x) > 40
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        false
    }

    @objc private func panned(_ pan: UIPanGestureRecognizer) {
        let translation = pan.translation(in: self).x
        switch pan.state {
        case .began, .changed:
            lockScroll()
            coordinator?.onChanged(translation)
        case .ended, .cancelled, .failed:
            let velocity = pan.velocity(in: self).x
            coordinator?.onEnded(translation, translation + velocity * 0.22)
            releaseScroll()
        default:
            break
        }
    }

    private func lockScroll() {
        guard lockedScroll == nil, let scroll = enclosingScrollView() else { return }
        lockedScroll = scroll
        scroll.isScrollEnabled = false
    }

    private func releaseScroll() {
        lockedScroll?.isScrollEnabled = true
        lockedScroll = nil
    }

    private func enclosingScrollView() -> UIScrollView? {
        var current = superview
        while let view = current {
            if let scroll = view as? UIScrollView { return scroll }
            current = view.superview
        }
        return nil
    }
}

private struct PageCornerHint: View {
    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: 28, y: 0))
            path.addLine(to: CGPoint(x: 28, y: 28))
            path.closeSubpath()
        }
        .fill(ScrapbookColors.paperEdge)
        .overlay {
            Path { path in
                path.move(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: 28, y: 28))
            }
            .stroke(ScrapbookColors.ink.opacity(0.28), lineWidth: 1)
        }
        .frame(width: 28, height: 28)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
