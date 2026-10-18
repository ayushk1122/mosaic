import CoreGraphics
import Foundation
import Testing

@testable import Mosaic

@Suite
struct ComposerBlockEdgeCaseTests {
    @Test
    func graphPlacementSurvivesExtremeValues() {
        let day = Date(timeIntervalSinceReferenceDate: 0)
        let points = [
            ComposerGraphPoint(id: "a", x: day, y: Int.max),
            ComposerGraphPoint(id: "b", x: day.addingTimeInterval(86_400), y: Int.min)
        ]
        let placed = ComposerLineGraph.placed(points)
        #expect(placed.count == 2)
        #expect(placed.allSatisfy { $0.ny.isFinite && (0...1).contains($0.ny) })
    }

    @Test
    func graphValuesAcceptSeparatorsAndRejectNonsense() {
        #expect(ComposerGraphValue.parse("1,000") == 1000)
        #expect(ComposerGraphValue.parse(" -42 ") == -42)
        #expect(ComposerGraphValue.parse("3.5") == nil)
        #expect(ComposerGraphValue.parse("") == nil)
        #expect(ComposerGraphValue.parse("9223372036854775807") == nil)
        #expect(ComposerGraphValue.parse("-9223372036854775808") == nil)
    }

    @Test
    func graphDatesKeepTheirDayAcrossTimeZones() throws {
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        let lateEvening = try #require(newYork.date(from: DateComponents(year: 2026, month: 10, day: 18, hour: 21)))
        let stored = ComposerLineGraph.day(lateEvening, calendar: newYork)

        var london = Calendar(identifier: .gregorian)
        london.timeZone = try #require(TimeZone(identifier: "Europe/London"))
        #expect(london.component(.day, from: stored) == 18)
        #expect(newYork.component(.day, from: stored) == 18)

        let morning = try #require(newYork.date(from: DateComponents(year: 2026, month: 10, day: 18, hour: 7)))
        #expect(ComposerLineGraph.day(morning, calendar: newYork) == stored)
    }

    @Test
    func calendarEntriesUseGregorianNumbersOnAnyDeviceCalendar() throws {
        var buddhist = Calendar(identifier: .buddhist)
        buddhist.firstWeekday = 2
        let entries = CalendarMonthModel.entryCalendar(from: buddhist)
        #expect(entries.identifier == .gregorian)
        #expect(entries.firstWeekday == 2)
        let date = try #require(Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 10, day: 18)))
        #expect(entries.component(.year, from: date) == 2026)
    }

    @Test
    func tabsAndBannersNeverJoinAGroup() {
        #expect(!ComposerGroupMath.canGroup(.tabs))
        #expect(!ComposerGroupMath.canGroup(.banner))
        #expect(ComposerGroupMath.canGroup(.text))

        let text = ComposerBlock.make(kind: .text, position: BlockPosition(x: 0, y: 0))
        let tabs = ComposerBlock.make(kind: .tabs, position: BlockPosition(x: 0, y: 0.5))
        let frames = [
            text.id: CGRect(x: 0, y: 0, width: 100, height: 40),
            tabs.id: CGRect(x: 0, y: 200, width: 300, height: 40)
        ]
        // Only one groupable piece remains, so no group is made.
        #expect(ComposerGroupMath.groupedBlock(
            members: [text, tabs], frames: frames, canvasWidth: 400, layoutHeight: 900, tabID: nil
        ) == nil)
    }

    @Test
    func ungroupingKeepsEachPieceWithinItsOwnLimits() {
        var graph = ComposerBlock.make(kind: .graph, position: BlockPosition(x: 0, y: 0))
        graph.graphHeightScale = 0.5
        ComposerGroupMath.bake(0.3, into: &graph)
        #expect(graph.graphHeightScale == ComposerGraphStretch.minimum)

        var text = ComposerBlock.make(kind: .text, position: BlockPosition(x: 0, y: 0))
        text.style.fontSize = 60
        ComposerGroupMath.bake(3, into: &text)
        #expect(text.style.fontSize == 80)

        var calendar = ComposerBlock.make(kind: .calendar, position: BlockPosition(x: 0, y: 0))
        calendar.style.scale = 0.6
        ComposerGroupMath.bake(0.45, into: &calendar)
        #expect(calendar.style.scale == 0.45)
    }
}
