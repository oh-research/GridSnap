import Foundation
import os

/// Nonisolated copy of the saved `Snapshot` list, read synchronously
/// from the CGEventTap callback thread. Written to by `SnapshotStore`
/// on every mutation. Separate from `SnapshotStore` because that type
/// is `@MainActor` for SwiftUI observation, which would prevent the
/// event-tap thread from calling in.
final class SnapshotLookupMirror: @unchecked Sendable {

    static let shared = SnapshotLookupMirror()

    private let lock = OSAllocatedUnfairLock<[Snapshot]>(initialState: [])

    private init() {}

    /// Replaces the mirrored list. Called from `SnapshotStore` after any
    /// persistence-visible change.
    func store(_ snapshots: [Snapshot]) {
        lock.withLock { $0 = snapshots }
    }

    /// First snapshot whose shortcut matches the key event, or `nil`.
    /// Safe to call from any thread.
    func lookup(keyCode: Int64, modifiers: PressedModifiers) -> Snapshot? {
        lock.withLock { list in
            list.first {
                $0.shortcut.keyCode == keyCode && $0.shortcut.modifiers == modifiers
            }
        }
    }
}
