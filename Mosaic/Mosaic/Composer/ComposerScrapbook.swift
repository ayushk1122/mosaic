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
    @State private var isGrouping = false
    @State private var pageWidth: CGFloat = 1

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
        .onPreferenceChange(ComposerGroupingPreferenceKey.self) { isGrouping = $0 }
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
                .layoutPriority(-1)
            Spacer(minLength: 8)
            pageTurnArrows
                .layoutPriority(1)
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
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityLabel("Scrapbook title")
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
                    .overlay(alignment: .topLeading) {
                        if !settling, !isGrouping, index > 0 {
                            pageTurnCorner(forward: false)
                                .padding(.leading, spiral)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if !settling, !isGrouping {
                            pageTurnCorner(forward: true)
                        }
                    }
                SpiralBinding(pageHeight: pageHeight, columnWidth: spiral)
                    .frame(width: spiral, height: pageHeight)
                    .overlay {
                        if !isGrouping {
                            ScrapbookSpineScroll()
                        }
                        if mediaObscured {
                            Color.black.opacity(0.94)
                                .allowsHitTesting(false)
                        }
                    }
            }
            .background {
                Color.clear
                    .onAppear { self.pageWidth = pageWidth }
                    .onChange(of: pageWidth) { _, width in
                        self.pageWidth = width
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
                    sheet(underneathID, number: (turningBack ? index : index + 1) + 1, pageHeight: pageHeight)
                    if let movingID {
                        sheet(movingID, number: (turningBack ? index - 1 : index) + 1, pageHeight: pageHeight)
                            .offset(x: movingOffset)
                            .shadow(color: .black.opacity(0.18), radius: 10, x: -6, y: 2)
                    }
                } else {
                    sheet(restingID, number: index + 1, pageHeight: pageHeight)
                }
            }
            .frame(width: pageWidth, height: pageHeight)
            .clipped()
        }
        .allowsHitTesting(abs(drag) < 1)
    }

    private func sheet(_ pageID: ComposerDocumentID?, number: Int, pageHeight: CGFloat) -> some View {
        ZStack(alignment: .topTrailing) {
            ScrapbookColors.paper
            if let pageID {
                MosaicComposerView(documentID: pageID, isBookPage: true)
                    .id(pageID)
                    .frame(height: pageHeight)
                    .clipped()
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

    private func pageTurnCorner(forward: Bool) -> some View {
        let enabled = forward ? canTurnForward : index > 0
        return ZStack(alignment: forward ? .topTrailing : .topLeading) {
            ScrapbookTurnSurface(turnsForward: forward) { translation in
                let directed = forward ? min(translation, 0) : max(translation, 0)
                followTurn(directed, pageWidth: pageWidth)
            } onEnded: { translation, predicted in
                let directed = forward ? min(translation, 0) : max(translation, 0)
                let predictedDirected = forward ? min(predicted, 0) : max(predicted, 0)
                finishTurn(translation: directed, predicted: predictedDirected, pageWidth: pageWidth)
            }
            PageCornerHint(leading: !forward, dimmed: mediaObscured)
                .padding(8)
                .opacity(abs(drag) < 1 ? 1 : 0)
                .allowsHitTesting(false)
        }
        .frame(width: 72, height: 72)
        .contentShape(Rectangle())
        .allowsHitTesting(enabled)
        .accessibilityLabel(forward ? "Next page" : "Previous page")
    }

    private var pageTurnArrows: some View {
        HStack(spacing: 8) {
            pageTurnArrow(forward: false)
            pageTurnArrow(forward: true)
        }
    }

    private func pageTurnArrow(forward: Bool) -> some View {
        let enabled = forward ? canTurnForward : index > 0
        return Button {
            turnByArrow(forward: forward, pageWidth: pageWidth)
        } label: {
            Image(systemName: forward ? "chevron.right" : "chevron.left")
                .font(.body.weight(.semibold))
                .foregroundStyle(.white.opacity(enabled ? 1 : 0.35))
                .frame(width: 36, height: 36)
                .background(Color.white.opacity(enabled ? 0.14 : 0.06), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled || settling)
        .accessibilityLabel(forward ? "Next page" : "Previous page")
    }

    private func turnByArrow(forward: Bool, pageWidth: CGFloat) {
        guard !settling else { return }
        let count = max(livePageIDs.count, 1)
        if forward {
            guard canTurnForward else { return }
            if index >= count - 1 {
                settling = true
                guard let created = store.insertScrapbookPage(after: index, on: blockID, in: parentDocumentID) else {
                    settling = false
                    return
                }
                revealTurn(forward: true)
                Task { @MainActor in
                    completeTurn(to: created, pageWidth: pageWidth, forward: true)
                }
                return
            }
        } else {
            guard index > 0 else { return }
        }
        let next = min(max(index + (forward ? 1 : -1), 0), count - 1)
        guard next != index else { return }
        settling = true
        store.rememberScrapbookPage(next, on: blockID, in: parentDocumentID)
        revealTurn(forward: forward)
        Task { @MainActor in
            completeTurn(to: next, pageWidth: pageWidth, forward: forward)
        }
    }

    private func revealTurn(forward: Bool) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            drag = forward ? -1 : 1
        }
    }

    private var canTurnForward: Bool {
        index < livePageIDs.count - 1 || (!chrome.isViewing && livePageIDs.count < 30)
    }

    private func followTurn(_ translation: CGFloat, pageWidth: CGFloat) {
        guard !settling else { return }
        if translation < 0 {
            let limit = canTurnForward ? pageWidth : pageWidth * 0.12
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
        let traveled = abs(drag)
        let flung = abs(predicted) > 90
        guard traveled > 48 || (flung && traveled > 20) else {
            cancelTurn()
            return
        }
        if forward, index >= count - 1 {
            guard !chrome.isViewing, count < 30 else {
                cancelTurn()
                return
            }
            settling = true
            guard let created = store.insertScrapbookPage(after: index, on: blockID, in: parentDocumentID) else {
                settling = false
                cancelTurn()
                return
            }
            completeTurn(to: created, pageWidth: pageWidth, forward: true)
            return
        }
        let next = min(max(index + (forward ? 1 : -1), 0), count - 1)
        guard next != index else {
            cancelTurn()
            return
        }
        settling = true
        store.rememberScrapbookPage(next, on: blockID, in: parentDocumentID)
        completeTurn(to: next, pageWidth: pageWidth, forward: forward)
    }

    private func cancelTurn() {
        withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) {
            drag = 0
        }
    }

    private func completeTurn(to next: Int, pageWidth: CGFloat, forward: Bool) {
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

/// A top-corner drag. The right corner turns forward and the left corner turns back.
private struct ScrapbookTurnSurface: UIViewRepresentable {
    var turnsForward: Bool
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
        uiView.turnsForward = turnsForward
    }

    final class Coordinator {
        var onChanged: (CGFloat) -> Void = { _ in }
        var onEnded: (CGFloat, CGFloat) -> Void = { _, _ in }
    }
}

private final class ScrapbookTurnView: UIView, UIGestureRecognizerDelegate {
    weak var coordinator: ScrapbookTurnSurface.Coordinator?
    var turnsForward = true
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
        guard abs(velocity.x) > abs(velocity.y) * 1.1, abs(velocity.x) > 40 else { return false }
        return turnsForward ? velocity.x < 0 : velocity.x > 0
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
    var leading = false
    var dimmed = false

    var body: some View {
        corner
            .fill(ScrapbookColors.paperEdge)
            .overlay {
                corner
                    .fill(Color.black.opacity(dimmed ? 0.94 : 0))
            }
            .overlay {
                Path { path in
                    path.move(to: leading ? CGPoint(x: 28, y: 0) : CGPoint(x: 0, y: 0))
                    path.addLine(to: leading ? CGPoint(x: 0, y: 28) : CGPoint(x: 28, y: 28))
                }
                .stroke(ScrapbookColors.ink.opacity(dimmed ? 0.08 : 0.28), lineWidth: 1)
            }
            .frame(width: 28, height: 28)
            .allowsHitTesting(false)
    }

    private var corner: Path {
        Path { path in
            if leading {
                path.move(to: CGPoint(x: 28, y: 0))
                path.addLine(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: 0, y: 28))
            } else {
                path.move(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: 28, y: 0))
                path.addLine(to: CGPoint(x: 28, y: 28))
            }
            path.closeSubpath()
        }
    }
}

/// Vertical drags on the spiral scroll the open page.
private struct ScrapbookSpineScroll: UIViewRepresentable {
    func makeUIView(context: Context) -> ScrapbookSpineScrollView {
        let view = ScrapbookSpineScrollView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = true
        return view
    }

    func updateUIView(_ uiView: ScrapbookSpineScrollView, context: Context) {}
}

private final class ScrapbookSpineScrollView: UIView {
    private var originY: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
        pan.cancelsTouchesInView = true
        addGestureRecognizer(pan)
    }

    required init?(coder: NSCoder) {
        nil
    }

    @objc private func panned(_ pan: UIPanGestureRecognizer) {
        guard let scroll = pageCanvasScroll() else { return }
        switch pan.state {
        case .began:
            originY = scroll.contentOffset.y
        case .changed:
            let maxOffset = max(scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom, 0)
            let next = min(max(originY - pan.translation(in: self).y, -scroll.adjustedContentInset.top), maxOffset)
            if !scroll.isScrollEnabled {
                scroll.isScrollEnabled = true
            }
            scroll.setContentOffset(CGPoint(x: 0, y: next), animated: false)
            ComposerCanvasScrollMark.report(scroll, offset: next)
        default:
            break
        }
    }

    /// The open page's scroller, which sits beside the spiral. Stops before the board scroller behind the book.
    private func pageCanvasScroll() -> UIScrollView? {
        var current: UIView? = self
        var depth = 0
        while let view = current, depth < 10 {
            if let parent = view.superview {
                for sibling in parent.subviews where sibling !== view {
                    if let found = sibling.firstTaggedCanvasScroll() {
                        return found
                    }
                }
                if parent is UIScrollView { return nil }
            }
            current = view.superview
            depth += 1
        }
        return nil
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
