import SwiftUI

enum CalendarMonthModel {
    struct Day: Equatable, Identifiable {
        var year: Int
        var month: Int
        var day: Int

        var id: String { String(format: "%04d-%02d-%02d", year, month, day) }
    }

    static func weeks(year: Int, month: Int, calendar: Calendar = .current) -> [[Day?]] {
        var components = DateComponents(year: year, month: month, day: 1)
        components.calendar = calendar
        guard let first = calendar.date(from: components) else { return [] }
        let weekday = calendar.component(.weekday, from: first)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        let dayCount = calendar.range(of: .day, in: .month, for: first)?.count ?? 0
        var cells: [Day?] = Array(repeating: nil, count: leading)
        if dayCount > 0 {
            for day in 1...dayCount {
                cells.append(Day(year: year, month: month, day: day))
            }
        }
        let remainder = cells.count % 7
        if remainder != 0 {
            cells.append(contentsOf: Array(repeating: nil, count: 7 - remainder))
        }
        guard !cells.isEmpty else { return [] }
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<($0 + 7)]) }
    }

    static func shifting(year: Int, month: Int, by months: Int, calendar: Calendar = .current) -> (year: Int, month: Int) {
        var components = DateComponents(year: year, month: month, day: 1)
        components.calendar = calendar
        guard let date = calendar.date(from: components),
              let shifted = calendar.date(byAdding: .month, value: months, to: date)
        else { return (year, month) }
        return (calendar.component(.year, from: shifted), calendar.component(.month, from: shifted))
    }

    static func title(year: Int, month: Int, calendar: Calendar = .current) -> String {
        var components = DateComponents(year: year, month: month, day: 1)
        components.calendar = calendar
        guard let date = calendar.date(from: components) else { return "" }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale ?? .current
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return formatter.string(from: date)
    }

    static func weekdaySymbols(calendar: Calendar = .current) -> [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        let start = max(calendar.firstWeekday - 1, 0)
        guard symbols.count == 7, start < symbols.count else { return symbols }
        return Array(symbols[start...] + symbols[..<start])
    }

    static func monthSymbols(calendar: Calendar = .current) -> [String] {
        calendar.shortMonthSymbols
    }

    static func dayTitle(year: Int, month: Int, day: Int, calendar: Calendar = .current) -> String {
        var components = DateComponents(year: year, month: month, day: day)
        components.calendar = calendar
        guard let date = calendar.date(from: components) else { return "" }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale ?? .current
        formatter.setLocalizedDateFormatFromTemplate("EEEE MMMM d")
        return formatter.string(from: date)
    }

    static func isToday(_ day: Day, now: Date = .now, calendar: Calendar = .current) -> Bool {
        let parts = calendar.dateComponents([.year, .month, .day], from: now)
        return parts.year == day.year && parts.month == day.month && parts.day == day.day
    }
}

struct ComposerCalendarCanvasBlock: View {
    @Binding var block: ComposerBlock
    let scale: CGFloat
    let livePinchScale: CGFloat
    let isLifted: Bool
    let isRelocating: Bool
    let isViewing: Bool

    @State private var year = Calendar.current.component(.year, from: .now)
    @State private var month = Calendar.current.component(.month, from: .now)
    @State private var showsYear = false
    @State private var selectedDay: CalendarMonthModel.Day?

    private var calendar: Calendar { .current }
    private var metric: CGFloat { max(0.45, scale * livePinchScale) }
    private var width: CGFloat { 332 * metric }
    private var canTap: Bool { !isLifted && !isRelocating }

    var body: some View {
        VStack(spacing: 10 * metric) {
            header
            if showsYear {
                yearGrid
            } else {
                weekdayRow
                dayGrid
            }
        }
        .padding(.horizontal, 10 * metric)
        .padding(.top, 12 * metric)
        .padding(.bottom, 6 * metric)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .frame(width: width)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        }
        .shadow(color: .white.opacity(isLifted ? 0.85 : 0), radius: isLifted ? 3 : 0)
        .shadow(color: .white.opacity(isLifted ? 0.4 : 0), radius: isLifted ? 14 : 0)
        .animation(.easeInOut(duration: 0.22), value: showsYear)
        .animation(.easeInOut(duration: 0.22), value: month)
        .animation(.easeInOut(duration: 0.22), value: year)
        .sheet(item: $selectedDay) { day in
            CalendarDaySheet(
                day: day,
                isViewing: isViewing,
                entry: block.calendarEntries.first { $0.id == day.id },
                onSave: { entry in
                    save(entry)
                }
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Calendar")
        .accessibilityIdentifier("composer.calendar")
    }

    private var header: some View {
        HStack(spacing: 8) {
            headerButton("chevron.left", label: showsYear ? "Previous year" : "Previous month") {
                step(-1)
            }
            Spacer(minLength: 0)
            headerTitle
            Spacer(minLength: 0)
            headerButton("chevron.right", label: showsYear ? "Next year" : "Next month") {
                step(1)
            }
        }
    }

    private var headerTitle: some View {
        Text(showsYear ? String(year) : CalendarMonthModel.title(year: year, month: month, calendar: calendar))
            .font(.system(size: 17 * metric, weight: .semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .contentShape(Rectangle())
            .simultaneousGesture(TapGesture().onEnded {
                guard canTap else { return }
                showsYear.toggle()
            })
            .accessibilityLabel(showsYear ? "Show days" : "Choose month")
            .accessibilityAddTraits(.isButton)
    }

    private func headerButton(_ systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 13 * metric, weight: .semibold))
            .foregroundStyle(.white.opacity(0.88))
            .frame(width: 28 * metric, height: 28 * metric)
            .contentShape(Rectangle())
            .simultaneousGesture(TapGesture().onEnded {
                guard canTap else { return }
                action()
            })
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
    }

    private var weekdayRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(CalendarMonthModel.weekdaySymbols(calendar: calendar).enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.system(size: 11 * metric, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.42))
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var dayGrid: some View {
        let weeks = CalendarMonthModel.weeks(year: year, month: month, calendar: calendar)
        return VStack(spacing: 2 * metric) {
            ForEach(0..<weeks.count, id: \.self) { week in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { column in
                        dayCell(weeks[week][column])
                    }
                }
            }
        }
    }

    private func dayCell(_ day: CalendarMonthModel.Day?) -> some View {
        let marked = day.map { hasContent($0) } ?? false
        let today = day.map { CalendarMonthModel.isToday($0, calendar: calendar) } ?? false
        return VStack(spacing: 2) {
            ZStack {
                if today {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 28 * metric, height: 28 * metric)
                }
                if let day {
                    Text("\(day.day)")
                        .font(.system(size: 15 * metric, weight: today ? .semibold : .regular))
                        .foregroundStyle(today ? MosaicBrand.inkBlack : .white.opacity(0.92))
                }
            }
            .frame(height: 28 * metric)
            Circle()
                .fill(Color.white.opacity(marked ? 0.9 : 0))
                .frame(width: 4 * metric, height: 4 * metric)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 38 * metric)
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded {
            guard canTap, let day else { return }
            selectedDay = day
        })
        .accessibilityLabel(day.map { CalendarMonthModel.dayTitle(year: $0.year, month: $0.month, day: $0.day, calendar: calendar) } ?? "")
        .accessibilityAddTraits(day == nil ? AccessibilityTraits() : .isButton)
    }

    private var yearGrid: some View {
        let symbols = CalendarMonthModel.monthSymbols(calendar: calendar)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8 * metric) {
            ForEach(Array(symbols.enumerated()), id: \.offset) { index, name in
                let monthNumber = index + 1
                let isCurrent = monthNumber == month
                Text(name)
                    .font(.system(size: 15 * metric, weight: isCurrent ? .semibold : .regular))
                    .foregroundStyle(isCurrent ? MosaicBrand.inkBlack : .white.opacity(0.9))
                    .frame(maxWidth: .infinity)
                    .frame(height: 36 * metric)
                    .background(
                        isCurrent ? Color.white : Color.white.opacity(0.06),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                    .contentShape(Rectangle())
                    .simultaneousGesture(TapGesture().onEnded {
                        guard canTap else { return }
                        month = monthNumber
                        showsYear = false
                    })
                    .accessibilityLabel(name)
                    .accessibilityAddTraits(.isButton)
            }
        }
        .padding(.vertical, 4 * metric)
    }

    private func step(_ delta: Int) {
        if showsYear {
            year += delta
        } else {
            let next = CalendarMonthModel.shifting(year: year, month: month, by: delta, calendar: calendar)
            year = next.year
            month = next.month
        }
    }

    private func hasContent(_ day: CalendarMonthModel.Day) -> Bool {
        block.calendarEntries.contains { $0.year == day.year && $0.month == day.month && $0.day == day.day && $0.hasContent }
    }

    private func save(_ entry: CalendarDayEntry) {
        if entry.hasContent {
            if let index = block.calendarEntries.firstIndex(where: { $0.id == entry.id }) {
                block.calendarEntries[index] = entry
            } else {
                block.calendarEntries.append(entry)
            }
        } else {
            block.calendarEntries.removeAll { $0.id == entry.id }
        }
    }
}

private struct CalendarDaySheet: View {
    let day: CalendarMonthModel.Day
    let isViewing: Bool
    let onSave: (CalendarDayEntry) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var note: String
    @State private var carousel: ComposerBlock
    @State private var showsCarouselEditor = false

    init(day: CalendarMonthModel.Day, isViewing: Bool, entry: CalendarDayEntry?, onSave: @escaping (CalendarDayEntry) -> Void) {
        self.day = day
        self.isViewing = isViewing
        self.onSave = onSave
        _note = State(initialValue: entry?.note ?? "")
        var block = ComposerBlock.make(kind: .carousel, position: .defaultPosition(index: 0))
        block.carouselItems = entry?.media ?? []
        block.carouselIndex = entry?.mediaIndex ?? 0
        _carousel = State(initialValue: block)
    }

    private var filledMedia: [CarouselMediaItem] {
        carousel.carouselItems.filter { !$0.fileName.isEmpty }
    }

    private var carouselReady: Bool {
        filledMedia.count >= CarouselMotion.minimumCount
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                media
                notes
                Spacer(minLength: 0)
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(MosaicBrand.inkBlack)
            .navigationTitle(CalendarMonthModel.dayTitle(year: day.year, month: day.month, day: day.day))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !isViewing {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            showsCarouselEditor = true
                        } label: {
                            Image(systemName: "rectangle.stack")
                        }
                        .accessibilityLabel("Edit media")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        commit()
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
        .sheet(isPresented: $showsCarouselEditor) {
            ComposerCarouselEditor(items: $carousel.carouselItems, index: $carousel.carouselIndex)
        }
        .onDisappear {
            commit()
        }
    }

    @ViewBuilder
    private var media: some View {
        if isViewing, filledMedia.isEmpty {
            Text("No media")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.45))
                .frame(maxWidth: .infinity, minHeight: 88)
        } else {
            ZStack {
                ComposerCarouselCanvasBlock(
                    block: $carousel,
                    scale: 1,
                    livePinchScale: 1,
                    isSelected: false,
                    isLifted: false,
                    isRelocating: false,
                    allowsDirectControl: carouselReady,
                    onEdit: {}
                )
                if !isViewing, !carouselReady {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { showsCarouselEditor = true }
                        .accessibilityLabel("Add media")
                        .accessibilityAddTraits(.isButton)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var notes: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notes")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.5))
            if isViewing {
                Text(note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No notes" : note)
                    .font(.body)
                    .foregroundStyle(.white.opacity(note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 0.92))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TextField("Write a note", text: $note, axis: .vertical)
                    .font(.body)
                    .foregroundStyle(.white)
                    .lineLimit(4...8)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func commit() {
        let media = carousel.carouselItems.filter { !$0.fileName.isEmpty }
        onSave(CalendarDayEntry(
            year: day.year,
            month: day.month,
            day: day.day,
            note: note,
            media: media,
            mediaIndex: media.isEmpty ? 0 : CarouselMotion.wrapped(carousel.carouselIndex, count: media.count)
        ))
    }
}
