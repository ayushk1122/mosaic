import SwiftUI

struct ComposerGraphCanvasBlock: View {
    @Binding var block: ComposerBlock
    let scale: CGFloat
    let livePinchScale: CGFloat
    let isLifted: Bool
    let isRelocating: Bool
    let isViewing: Bool

    @State private var selectedPointID: String?
    @State private var showsEditor = false
    @GestureState private var widthDrag: CGFloat = 1
    @GestureState private var heightDrag: CGFloat = 1
    @State private var resizeFrames = ComposerGraphResizeFrames()

    private var widthScale: CGFloat {
        CGFloat(block.graphWidthScale) * scale * widthDrag * livePinchScale
    }

    private var heightScale: CGFloat {
        CGFloat(block.graphHeightScale) * scale * heightDrag * livePinchScale
    }

    private var width: CGFloat { ComposerGraphStretch.baseWidth * widthScale }
    private var height: CGFloat { ComposerGraphStretch.baseHeight * heightScale }
    private var metric: CGFloat { min(max(min(widthScale, heightScale), 0.75), 1.45) }
    private var canTap: Bool { !isLifted && !isRelocating }
    private var showsHandles: Bool { !isViewing && !isLifted && !isRelocating }

    private var placed: [ComposerLineGraph.Placed] {
        ComposerLineGraph.placed(block.graphPoints)
    }

    private var title: String {
        let trimmed = block.graphTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Graph" : trimmed
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            plot
            Text(title)
                .font(.system(size: 16 * metric, weight: .semibold))
                .foregroundStyle(.white.opacity(block.graphTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 0.95))
                .lineLimit(1)
                .padding(.top, 12 * metric)
                .padding(.leading, 14 * metric)
                .padding(.trailing, isViewing ? 14 * metric : 48 * metric)
            if !isViewing {
                addButton
                    .padding(10 * metric)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
        .frame(width: width, height: height)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        }
        .shadow(color: .white.opacity(isLifted ? 0.85 : 0), radius: isLifted ? 3 : 0)
        .shadow(color: .white.opacity(isLifted ? 0.4 : 0), radius: isLifted ? 14 : 0)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay { if showsHandles { resizeHandles } }
        .preference(key: ComposerGraphResizeFrameKey.self, value: showsHandles ? [block.id: resizeFrames] : [:])
        .sheet(isPresented: $showsEditor) {
            GraphPointEditor(block: $block)
        }
        .onChange(of: block.graphPoints.map(\.id)) { _, ids in
            if let selectedPointID, !ids.contains(selectedPointID) {
                self.selectedPointID = nil
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Graph")
        .accessibilityIdentifier("composer.graph")
    }

    private var resizeHandles: some View {
        ZStack {
            edgeHandle(horizontal: true, leadingOrTop: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            edgeHandle(horizontal: true, leadingOrTop: false)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            edgeHandle(horizontal: false, leadingOrTop: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            edgeHandle(horizontal: false, leadingOrTop: false)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }

    private func edgeHandle(horizontal: Bool, leadingOrTop: Bool) -> some View {
        Capsule()
            .fill(Color.white.opacity(0.92))
            .frame(width: horizontal ? 6 : 34, height: horizontal ? 34 : 6)
            .padding(horizontal ? .horizontal : .vertical, 4)
            .contentShape(Rectangle())
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named("composerRoot"))
            } action: { frame in
                switch (horizontal, leadingOrTop) {
                case (true, true): resizeFrames.leading = frame
                case (true, false): resizeFrames.trailing = frame
                case (false, true): resizeFrames.top = frame
                case (false, false): resizeFrames.bottom = frame
                }
            }
            .highPriorityGesture(resizeGesture(horizontal: horizontal, leadingOrTop: leadingOrTop))
            .accessibilityLabel(horizontal
                ? (leadingOrTop ? "Stretch width from the left" : "Stretch width from the right")
                : (leadingOrTop ? "Stretch height from the top" : "Stretch height from the bottom"))
            .accessibilityAddTraits(.isButton)
    }

    private func resizeGesture(horizontal: Bool, leadingOrTop: Bool) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("composerRoot"))
            .updating(horizontal ? $widthDrag : $heightDrag) { value, state, _ in
                let base = horizontal
                    ? block.graphWidthScale * Double(scale)
                    : block.graphHeightScale * Double(scale)
                let translation = horizontal ? value.translation.width : value.translation.height
                let span = horizontal ? ComposerGraphStretch.baseWidth : ComposerGraphStretch.baseHeight
                let next = ComposerGraphStretch.resized(
                    base: base,
                    translation: translation,
                    span: span,
                    leadingOrTop: leadingOrTop
                )
                state = CGFloat(next / max(base, 0.01))
            }
            .onEnded { value in
                let translation = horizontal ? value.translation.width : value.translation.height
                let span = horizontal ? ComposerGraphStretch.baseWidth : ComposerGraphStretch.baseHeight
                let widthBase = block.graphWidthScale * Double(scale)
                let heightBase = block.graphHeightScale * Double(scale)
                if horizontal {
                    block.graphWidthScale = ComposerGraphStretch.resized(
                        base: widthBase,
                        translation: translation,
                        span: span,
                        leadingOrTop: leadingOrTop
                    )
                    block.graphHeightScale = ComposerGraphStretch.clamped(heightBase)
                } else {
                    block.graphHeightScale = ComposerGraphStretch.resized(
                        base: heightBase,
                        translation: translation,
                        span: span,
                        leadingOrTop: leadingOrTop
                    )
                    block.graphWidthScale = ComposerGraphStretch.clamped(widthBase)
                }
                block.style.scale = 1
            }
    }

    private var plot: some View {
        let points = placed
        return ZStack {
            axisPath
            linePath(points)
            ForEach(points, id: \.id) { point in
                pointMark(point)
                    .position(canvasPoint(point))
            }
            if points.isEmpty, !isViewing {
                Text("Add a point")
                    .font(.system(size: 14 * metric, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .simultaneousGesture(TapGesture().onEnded {
                        guard canTap else { return }
                        showsEditor = true
                    })
            }
        }
        .frame(width: width, height: height)
    }

    private var axisPath: some View {
        Path { path in
            let rect = plotRect
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        }
        .stroke(Color.white.opacity(0.28), lineWidth: 1)
    }

    private func linePath(_ points: [ComposerLineGraph.Placed]) -> some View {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: canvasPoint(first))
            for point in points.dropFirst() {
                path.addLine(to: canvasPoint(point))
            }
        }
        .stroke(
            Color.white.opacity(points.count > 1 ? 0.92 : 0),
            style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
        )
    }

    private func pointMark(_ placedPoint: ComposerLineGraph.Placed) -> some View {
        let point = block.graphPoints.first { $0.id == placedPoint.id }
        let selected = selectedPointID == placedPoint.id
        return ZStack {
            Text(point.map { "\($0.y)" } ?? "")
                .font(.system(size: 11 * metric, weight: .semibold))
                .foregroundStyle(.white)
                .offset(y: -16 * metric)
            Circle()
                .fill(Color.white)
                .frame(width: (selected ? 11 : 8) * metric, height: (selected ? 11 : 8) * metric)
            if selected, let point {
                Text(ComposerLineGraph.dateLabel(point.x))
                    .font(.system(size: 11 * metric, weight: .medium))
                    .foregroundStyle(MosaicBrand.inkBlack)
                    .padding(.horizontal, 7 * metric)
                    .padding(.vertical, 3 * metric)
                    .background(Color.white, in: Capsule())
                    .offset(y: 18 * metric)
            }
        }
        .frame(width: 76 * metric, height: 56 * metric)
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded {
            guard canTap else { return }
            selectedPointID = selected ? nil : placedPoint.id
        })
        .accessibilityLabel(point.map { "\($0.y), \(ComposerLineGraph.dateLabel($0.x))" } ?? "Point")
        .accessibilityAddTraits(.isButton)
    }

    private var addButton: some View {
        Image(systemName: "plus")
            .font(.system(size: 13 * metric, weight: .semibold))
            .foregroundStyle(.white.opacity(0.92))
            .frame(width: 28 * metric, height: 28 * metric)
            .background(Color(red: 0.20, green: 0.21, blue: 0.23), in: Circle())
            .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
            .contentShape(Circle())
            .simultaneousGesture(TapGesture().onEnded {
                guard canTap else { return }
                showsEditor = true
            })
            .accessibilityLabel("Add point")
            .accessibilityAddTraits(.isButton)
    }

    private var plotRect: CGRect {
        CGRect(x: 18 * metric, y: 44 * metric, width: width - 32 * metric, height: height - 62 * metric)
    }

    private func canvasPoint(_ placedPoint: ComposerLineGraph.Placed) -> CGPoint {
        let rect = plotRect.insetBy(dx: 10 * metric, dy: 18 * metric)
        return CGPoint(
            x: rect.minX + placedPoint.nx * rect.width,
            y: rect.maxY - placedPoint.ny * rect.height
        )
    }
}

private struct GraphPointEditor: View {
    @Binding var block: ComposerBlock
    @Environment(\.dismiss) private var dismiss

    @State private var draftDate = Date.now
    @State private var draftY = ""

    private var orderedPoints: [ComposerGraphPoint] {
        let order = ComposerLineGraph.placed(block.graphPoints).map(\.id)
        return order.compactMap { id in block.graphPoints.first { $0.id == id } }
    }

    private var xName: String {
        let trimmed = block.graphXUnitName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Date" : trimmed
    }

    private var yName: String {
        let trimmed = block.graphYUnitName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Value" : trimmed
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    field("Title", text: $block.graphTitle, prompt: "Graph")
                    field("X unit", text: $block.graphXUnitName, prompt: "Date")
                    field("Y unit", text: $block.graphYUnitName, prompt: "Value")
                    Text("X is a date. Y is a whole number.")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.5))

                    if !orderedPoints.isEmpty {
                        VStack(spacing: 8) {
                            ForEach(orderedPoints) { point in
                                HStack {
                                    Text(ComposerLineGraph.dateLabel(point.x))
                                    Spacer()
                                    Text("\(point.y)")
                                        .monospacedDigit()
                                    Button {
                                        block.graphPoints.removeAll { $0.id == point.id }
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.caption2.weight(.bold))
                                            .frame(width: 22, height: 22)
                                    }
                                    .accessibilityLabel("Remove point")
                                }
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.92))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        DatePicker(xName, selection: $draftDate, displayedComponents: .date)
                            .datePickerStyle(.compact)
                        TextField(yName, text: $draftY, prompt: Text("0").foregroundStyle(.white.opacity(0.35)))
                            .keyboardType(.numbersAndPunctuation)
                        Button {
                            addPoint()
                        } label: {
                            Text("Add point")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .foregroundStyle(MosaicBrand.inkBlack)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(14)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .foregroundStyle(.white)
                }
                .padding(20)
            }
            .background(MosaicBrand.inkBlack)
            .navigationTitle("Graph")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(MosaicBrand.inkBlack)
    }

    private func field(_ label: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.5))
            TextField("", text: text, prompt: Text(prompt).foregroundStyle(.white.opacity(0.35)))
                .font(.body)
                .foregroundStyle(.white)
                .padding(12)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func addPoint() {
        let trimmed = draftY.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let y = Int(trimmed) else { return }
        block.graphPoints.append(ComposerGraphPoint(x: draftDate, y: y))
        draftY = ""
    }
}

struct ComposerGraphResizeFrames: Equatable {
    var leading = CGRect.zero
    var trailing = CGRect.zero
    var top = CGRect.zero
    var bottom = CGRect.zero

    func contains(_ point: CGPoint) -> Bool {
        [leading, trailing, top, bottom].contains { frame in
            frame.width > 1 && frame.insetBy(dx: -10, dy: -10).contains(point)
        }
    }
}

struct ComposerGraphResizeFrameKey: PreferenceKey {
    static var defaultValue: [ComposerBlockID: ComposerGraphResizeFrames] = [:]

    static func reduce(
        value: inout [ComposerBlockID: ComposerGraphResizeFrames],
        nextValue: () -> [ComposerBlockID: ComposerGraphResizeFrames]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}
