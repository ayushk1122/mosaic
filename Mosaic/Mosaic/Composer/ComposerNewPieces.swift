import SwiftUI

private struct ComposerNewBoardsKey: EnvironmentKey {
    static let defaultValue: Set<UUID> = []
}

private struct ComposerShowsBackKey: EnvironmentKey {
    static let defaultValue = true
}

private struct ComposerTopInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

private struct ComposerCloseKey: EnvironmentKey {
    static let defaultValue: (@MainActor () -> Void)? = nil
}

extension EnvironmentValues {
    /// Nodes and pages with something new inside; the pieces that open them are marked too.
    var composerNewBoards: Set<UUID> {
        get { self[ComposerNewBoardsKey.self] }
        set { self[ComposerNewBoardsKey.self] = newValue }
    }

    /// Off for a board shown as a page of Orbit, which has nothing to go back to.
    var composerShowsBack: Bool {
        get { self[ComposerShowsBackKey.self] }
        set { self[ComposerShowsBackKey.self] = newValue }
    }

    /// Room at the top for something laid over the board, like Orbit's header: the board's content
    /// and controls start below it, and the board scrolls beneath it.
    var composerTopInset: CGFloat {
        get { self[ComposerTopInsetKey.self] }
        set { self[ComposerTopInsetKey.self] = newValue }
    }

    /// Closes a Mosaic opened over an Orbit page; its back arrow and swipe use this instead of
    /// going back on a navigation stack.
    var composerClose: (@MainActor () -> Void)? {
        get { self[ComposerCloseKey.self] }
        set { self[ComposerCloseKey.self] = newValue }
    }
}

/// Whether a journal is open on the board, or on one opened from it.
struct ComposerJournalOpenKey: PreferenceKey {
    static let defaultValue = false

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}
