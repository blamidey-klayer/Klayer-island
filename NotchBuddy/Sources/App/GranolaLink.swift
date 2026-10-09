import Foundation

/// The Granola shortcut of the compact island (spec §5) and of the home's rail (lot 6 spec §2).
/// Foundation only: the test script compiles this file alone. The SwiftUI `GranolaButton`
/// (IslandRootView.swift) and the rail's icon (OverviewView) pass the production opener,
/// `NSWorkspace.shared.open`.
enum GranolaLink {
    /// Creates a note in Granola. Whether it also starts the recording is not confirmed (spike S4).
    static let newNote = URL(string: "granola://new-document")!

    /// Hands `newNote` to `opener` once and returns its answer (`false` when no app answers
    /// the `granola://` scheme, for instance when Granola is not installed).
    @discardableResult
    static func open(using opener: (URL) -> Bool) -> Bool {
        opener(newNote)
    }
}
