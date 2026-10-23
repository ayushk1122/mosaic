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

    private var widthScale: CGFloat {
        CGFloat(block.graphWidthScale) * scale * livePinchScale
    }

    private var heightScale: CGFloat {
        CGFloat(block.graphHeightScale) * scale * livePinchScale
    }

    private var width: CGFloat { ComposerGraphStretch.baseWidth * widthScale }
    private var height: CGFloat { ComposerGraphStretch.baseHeight * heightScale }
    private var metric: CGFloat { min(max(min(widthScale, heightScale), 0.75), 1.45) }
    private var canTap: Bool { !isLifted && !isRelocating }

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

    private var plot: some View {
        let points = placed
        return ZStack {
            axisPath
            linePath(points)
            ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                pointMark(point)
                    .updateAnchor("\(block.id.rawValue.lowercased())/graphpoints/\(point.id.lowercased())", order: index)
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
        CGRect(x: 18 * metric, y: 44 * metric, width: max(width - 32 * metric, 1), height: max(height - 62 * metric, 1))
    }

    /// Insets never exceed half the plot, so a very short graph doesn't produce a null rect
    /// (whose infinite origin would send every point off screen).
    private func canvasPoint(_ placedPoint: ComposerLineGraph.Placed) -> CGPoint {
        let plot = plotRect
        let insetX = min(10 * metric, plot.width / 2)
        let insetY = min(18 * metric, plot.height / 2)
        let rect = CGRect(
            x: plot.minX + insetX,
            y: plot.minY + insetY,
            width: max(plot.width - 2 * insetX, 0),
            height: max(plot.height - 2 * insetY, 0)
        )
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
    @State private var draftProblem: String?

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
                            .onChange(of: draftY) { _, _ in draftProblem = nil }
                        if let draftProblem {
                            Text(draftProblem)
                                .font(.caption)
                                .foregroundStyle(Color(red: 1, green: 0.55, blue: 0.5))
                        }
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
                    Button("Done") {
                        // A typed value that wasn't added yet is kept, not silently dropped.
                        if !draftY.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            guard addPoint() else { return }
                        }
                        dismiss()
                    }
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

    @discardableResult
    private func addPoint() -> Bool {
        guard let y = ComposerGraphValue.parse(draftY) else {
            draftProblem = "Enter a whole number, like 72 or 1,000."
            return false
        }
        block.graphPoints.append(ComposerGraphPoint(x: ComposerLineGraph.day(draftDate), y: y))
        draftY = ""
        draftProblem = nil
        return true
    }
}

enum ComposerGraphValue {
    /// Whole numbers within ±1 trillion. Thousands separators and spaces are allowed.
    static func parse(_ text: String) -> Int? {
        let cleaned = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "_", with: "")
        guard let value = Int(cleaned), (-1_000_000_000_000...1_000_000_000_000).contains(value) else { return nil }
        return value
    }
}

