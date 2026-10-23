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
    @MainActor
    func leavingCircleReturnsThePhotoToItsOwnShape() throws {
        let store = ComposerStore(seedSnapshot: .empty, persistToDisk: false)
        let photo = store.addBlock(.media, to: nil)
        store.setLook(photoShape: .circle, for: photo, in: nil)
        #expect(store.block(with: photo, in: nil)?.mediaFrameAspect == 1)
        store.setLook(photoShape: .roundedRectangle, for: photo, in: nil)
        let rounded = try #require(store.block(with: photo, in: nil))
        #expect(rounded.mediaShape == .roundedRectangle)
        #expect(rounded.mediaFrameAspect == 0)
    }

    @Test
    func floatingControlsStayOnScreen() {
        let visible = CGRect(x: 0, y: 1000, width: 400, height: 700)
        let size = CGSize(width: 200, height: 34)

        // Room above: centered over the piece.
        let middle = ComposerChromePlacement.floating(size: size, around: CGRect(x: 100, y: 1300, width: 200, height: 100), visible: visible)
        #expect(middle.origin == CGPoint(x: 100, y: 1256))
        #expect(!middle.isBelow)

        // Near the left edge: slides inward.
        let left = ComposerChromePlacement.floating(size: size, around: CGRect(x: -20, y: 1300, width: 80, height: 80), visible: visible)
        #expect(left.origin.x == 8)

        // Near the right edge: slides inward.
        let right = ComposerChromePlacement.floating(size: size, around: CGRect(x: 360, y: 1300, width: 80, height: 80), visible: visible)
        #expect(right.origin.x == 192)

        // Near the top of the screen: flips below.
        let top = ComposerChromePlacement.floating(size: size, around: CGRect(x: 100, y: 1010, width: 200, height: 100), visible: visible)
        #expect(top.isBelow)
        #expect(top.origin.y == 1120)

        // Taller than the screen: pinned inside the visible area.
        let tall = ComposerChromePlacement.floating(size: size, around: CGRect(x: 0, y: 900, width: 400, height: 1200), visible: visible)
        #expect(tall.origin.y == 1008)

        // Fits neither above nor below: held against the side with more room, covering little of the piece.
        let tallPanel = CGSize(width: 260, height: 260)
        let squeezed = ComposerChromePlacement.floating(size: tallPanel, around: CGRect(x: 100, y: 1200, width: 200, height: 240), visible: visible)
        #expect(squeezed.isBelow)
        #expect(squeezed.origin.y == visible.maxY - 8 - tallPanel.height)
        let squeezedHigh = ComposerChromePlacement.floating(size: tallPanel, around: CGRect(x: 100, y: 1250, width: 200, height: 300), visible: visible)
        #expect(!squeezedHigh.isBelow)
        #expect(squeezedHigh.origin.y == visible.minY + 8)

        // Scrolled off the top or bottom: the control stays at the nearer edge.
        let offTop = ComposerChromePlacement.floating(size: size, around: CGRect(x: 100, y: 700, width: 200, height: 100), visible: visible)
        #expect(offTop.origin.y == visible.minY + 8)
        let offBottom = ComposerChromePlacement.floating(size: size, around: CGRect(x: 100, y: 1900, width: 200, height: 100), visible: visible)
        #expect(offBottom.origin.y == visible.maxY - 8 - size.height)

        // At the finger on a tall piece.
        let finger = ComposerChromePlacement.floating(size: size, around: CGRect(x: 0, y: 900, width: 400, height: 1200), visible: visible, anchorY: 1400)
        #expect(finger.origin.y == 1356)
    }

    @Test
    func rotationSnapsAndStaysInRange() {
        #expect(ComposerRotation.normalized(370) == 10)
        #expect(ComposerRotation.normalized(-190) == 170)
        #expect(ComposerRotation.normalized(180) == 180)
        #expect(ComposerRotation.normalized(.nan) == 0)
        #expect(ComposerRotation.snapped(3) == (0, true))
        #expect(ComposerRotation.snapped(-43) == (-45, true))
        #expect(ComposerRotation.snapped(178) == (180, true))
        #expect(ComposerRotation.snapped(-178) == (180, true))
        #expect(ComposerRotation.snapped(27) == (27, false))
    }

    @Test
    func handleDirectionIsTheAngle() {
        #expect(ComposerRotation.handleAngle(fromCenterTo: CGSize(width: 0, height: -50)) == 0)
        #expect(abs(ComposerRotation.handleAngle(fromCenterTo: CGSize(width: 50, height: 0)) - 90) < 0.001)
        #expect(abs(ComposerRotation.handleAngle(fromCenterTo: CGSize(width: -50, height: 0)) + 90) < 0.001)
        #expect(abs(ComposerRotation.handleAngle(fromCenterTo: CGSize(width: 0, height: 50)) - 180) < 0.001)
    }

    @Test
    func onlyVisualUnlockedPiecesRotate() throws {
        #expect(ComposerBlock.make(kind: .media, position: BlockPosition(x: 0, y: 0)).canRotate)
        #expect(ComposerBlock.make(kind: .group, position: BlockPosition(x: 0, y: 0)).canRotate)
        #expect(!ComposerBlock.make(kind: .table, position: BlockPosition(x: 0, y: 0)).canRotate)
        #expect(!ComposerBlock.make(kind: .tabs, position: BlockPosition(x: 0, y: 0)).canRotate)
    }

    @Test
    func ungroupingATiltedGroupTurnsMembersAroundItsCenter() throws {
        var member = ComposerBlock.make(kind: .media, position: BlockPosition(x: 0, y: 0))
        member.rotation = 10
        var group = ComposerBlock.make(kind: .group, position: BlockPosition(x: 0, y: 0))
        group.groupMembers = [member]
        group.groupWidth = 200
        group.groupHeight = 100
        group.rotation = 90

        // A 100×100 member at the group's left half: its center (50, 50) turns 90° clockwise
        // around the group's center (100, 50) to (100, 0), so its top-left lands at (50, -50).
        let restored = ComposerGroupMath.ungroupedMembers(
            of: group,
            canvasWidth: 1000,
            layoutHeight: 1000,
            memberSizes: [member.id: CGSize(width: 100, height: 100)]
        )
        let out = try #require(restored.first)
        #expect(out.rotation == 100)
        #expect(abs(out.position.x * 1000 - 50) < 0.5)
        #expect(abs(out.position.y * 1000 - -50) < 0.5)
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
