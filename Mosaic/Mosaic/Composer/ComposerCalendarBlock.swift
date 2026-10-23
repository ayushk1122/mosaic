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

    /// Entries are saved as year/month/day numbers, so they must always be Gregorian numbers.
    /// A Buddhist or Japanese device calendar would otherwise save years another device misreads.
    /// The user's locale, time zone, and first weekday still apply.
    static func entryCalendar(from current: Calendar = .current) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = current.locale
        calendar.timeZone = current.timeZone
        calendar.firstWeekday = current.firstWeekday
        return calendar
    }
}

struct ComposerCalendarCanvasBlock: View {
    @Binding var block: ComposerBlock
    let scale: CGFloat
    let livePinchScale: CGFloat
    let isLifted: Bool
    let isRelocating: Bool
    let isViewing: Bool

    @Environment(\.composerPaperPage) private var onPaper
    @Environment(\.composerUpdateAddresses) private var updateAddresses
    @Environment(ComposerUpdateGuide.self) private var updateGuide: ComposerUpdateGuide?
    @State private var year = CalendarMonthModel.entryCalendar().component(.year, from: .now)
    @State private var month = CalendarMonthModel.entryCalendar().component(.month, from: .now)
    @State private var showsYear = false
    @State private var selectedDay: CalendarMonthModel.Day?
    /// Bumped at midnight so the "today" circle moves without waiting for another redraw.
    @State private var dayTick = 0

    private var calendar: Calendar { CalendarMonthModel.entryCalendar() }
    private var pieceKey: String { block.id.rawValue.lowercased() }

    private var daysPrefix: String { "\(pieceKey)/calendarentries/" }

    private func address(of day: CalendarMonthModel.Day) -> String {
        daysPrefix + ComposerUpdateAddress.day(year: day.year, month: day.month, day: day.day)
    }

    /// On a board opened from Orbit, the days with updates by address, ordered by date.
    private var updatedDays: [String: Int] {
        guard updateGuide != nil else { return [:] }
        var days: [String: Int] = [:]
        for address in updateAddresses where address.hasPrefix(daysPrefix) {
            let part = String(address.dropFirst(daysPrefix.count).split(separator: "/").first ?? "")
            guard let date = ComposerUpdateAddress.date(of: part) else { continue }
            days[daysPrefix + part] = date.year * 10_000 + date.month * 100 + date.day
        }
        return days
    }

    /// Days with updates outside the month shown, which have a place in the navigator's order at the calendar.
    private var hiddenDays: [String: Int] {
        updatedDays.filter { address, _ in
            guard !showsYear, let date = ComposerUpdateAddress.date(of: String(address.dropFirst(daysPrefix.count))) else { return true }
            return date.year != year || date.month != month
        }
    }
    private var metric: CGFloat { max(0.45, scale * livePinchScale) }
    private var width: CGFloat { 332 * metric }
    private var canTap: Bool { !isLifted && !isRelocating }
    /// Paper pages need the same dark card as Mosaic / Pursuit so the grid stays readable.
    private var cardFill: Color {
        onPaper ? Color(red: 0.20, green: 0.21, blue: 0.23) : Color.white.opacity(0.05)
    }

    var body: some View {
        let _ = dayTick
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
        .hiddenUpdateAnchors(hiddenDays)
        .background(cardFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(onPaper ? 0.14 : 0.1), lineWidth: 1)
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
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            Task { @MainActor in dayTick += 1 }
        }
        .onChange(of: selectedDay) { _, day in
            // Opening a day shows what was added to it.
            guard let day else { return }
            let seen = updateAddresses.filter { ComposerUpdateAddress.isWithin($0, address(of: day)) }
            if !seen.isEmpty { updateGuide?.markSeen(Set(seen)) }
        }
        // Orbit's navigator: a day in another month is shown by turning to its month.
        .revealHost("calendar:\(pieceKey)", claim: { address in
            address.hasPrefix(daysPrefix) ? pieceKey.count + 1 : nil
        }, reveal: { address in
            guard let asked = ComposerUpdateAddress.date(of: String(
                address.dropFirst(daysPrefix.count).split(separator: "/").first ?? ""
            )) else { return }
            showsYear = false
            withAnimation(.easeInOut(duration: 0.25)) {
                year = asked.year
                month = asked.month
            }
        }, open: { address in
            // There: open the day, to see what was added to it. Opening it checks it off.
            guard let asked = ComposerUpdateAddress.date(of: String(
                address.dropFirst(daysPrefix.count).split(separator: "/").first ?? ""
            )) else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(450))
                selectedDay = CalendarMonthModel.Day(year: asked.year, month: asked.month, day: asked.day)
            }
        })
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
            // A day with an update glows; the address is empty for the grid's blank cells.
            .updateAnchor(day.map(address(of:)) ?? "", order: day.map { $0.year * 10_000 + $0.month * 100 + $0.day } ?? 0)
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

enum CalendarDayNotes {
    /// Notes start closed, and open on their own once they have something written.
    static func opensAtFirst(_ note: String) -> Bool {
        !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
    @State private var notesOpen: Bool
    @State private var focusedMedia: CalendarFocusedMedia?
    @FocusState private var noteFocused: Bool

    init(day: CalendarMonthModel.Day, isViewing: Bool, entry: CalendarDayEntry?, onSave: @escaping (CalendarDayEntry) -> Void) {
        self.day = day
        self.isViewing = isViewing
        self.onSave = onSave
        let note = entry?.note ?? ""
        _note = State(initialValue: note)
        _notesOpen = State(initialValue: CalendarDayNotes.opensAtFirst(note))
        var block = ComposerBlock.make(kind: .carousel, position: .defaultPosition(index: 0))
        block.carouselItems = entry?.media ?? []
        block.carouselIndex = entry?.mediaIndex ?? 0
        _carousel = State(initialValue: block)
    }

    private var filledMedia: [CarouselMediaItem] {
        carousel.carouselItems.filter(\.hasContent)
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
                        .accessibilityLabel("Edit items")
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
        // A sheet sits above the board's own viewer, so the day presents its own, without the slide-up.
        .fullScreenCover(item: $focusedMedia) { focused in
            ComposerMediaLightbox(url: focused.url) {
                withoutPresentationAnimation { focusedMedia = nil }
            }
            .presentationBackground(.clear)
        }
        .onDisappear {
            commit()
        }
    }

    @ViewBuilder
    private var media: some View {
        if isViewing, filledMedia.isEmpty {
            Text("Nothing added")
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
                    onEdit: {},
                    onPresentMedia: { url, _ in
                        withoutPresentationAnimation { focusedMedia = CalendarFocusedMedia(url: url) }
                    },
                    opensLinks: true
                )
                if !isViewing, !carouselReady {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { showsCarouselEditor = true }
                        .accessibilityLabel("Add items")
                        .accessibilityAddTraits(.isButton)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var notes: some View {
        if !isViewing || CalendarDayNotes.opensAtFirst(note) {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        notesOpen.toggle()
                    }
                    noteFocused = notesOpen && !isViewing
                } label: {
                    HStack {
                        Text("Notes")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.5))
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.5))
                            .rotationEffect(.degrees(notesOpen ? 0 : -90))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(notesOpen ? "Hide notes" : "Show notes")
                .accessibilityIdentifier("calendar.notes.toggle")
                if notesOpen {
                    if isViewing {
                        Text(note)
                            .font(.body)
                            .foregroundStyle(.white.opacity(0.92))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        TextField("Write a note", text: $note, axis: .vertical)
                            .font(.body)
                            .foregroundStyle(.white)
                            .lineLimit(4...8)
                            .focused($noteFocused)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func commit() {
        let media = carousel.carouselItems.filter(\.hasContent)
        onSave(CalendarDayEntry(
            year: day.year,
            month: day.month,
            day: day.day,
            note: note,
            media: media,
            mediaIndex: media.isEmpty ? 0 : CarouselMotion.wrapped(carousel.carouselIndex, count: media.count)
        ))
    }

    private func withoutPresentationAnimation(_ change: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, change)
    }
}

private struct CalendarFocusedMedia: Identifiable {
    let url: URL
    var id: URL { url }
}
