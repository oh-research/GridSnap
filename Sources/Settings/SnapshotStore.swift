import Foundation
import Observation
import os

/// Persists user-saved `Snapshot`s in `UserDefaults` (JSON). The list
/// is observable by SwiftUI (main-actor). Fast `(keyCode, modifiers)`
/// matching from the CGEventTap thread happens via
/// `SnapshotLookupMirror.shared`, kept in sync by `persist()`.
@MainActor
@Observable
final class SnapshotStore {

    static let shared = SnapshotStore()

    private static let defaultsKey = "snapshots.v1"

    private(set) var snapshots: [Snapshot] = []

    private init() {
        load()
    }

    // MARK: - Mutation

    /// Adds `snapshot`, failing if another saved snapshot already uses the
    /// same shortcut.
    @discardableResult
    func add(_ snapshot: Snapshot) -> Result<Void, MutationError> {
        if let err = snapshot.shortcut.validate() {
            return .failure(.invalidShortcut(err))
        }
        if snapshots.contains(where: { $0.shortcut == snapshot.shortcut }) {
            return .failure(.shortcutTaken)
        }
        snapshots.append(snapshot)
        persist()
        return .success(())
    }

    /// Replaces an existing snapshot's shortcut. Same collision rule as `add`.
    @discardableResult
    func updateShortcut(id: UUID, to shortcut: ShortcutSpec) -> Result<Void, MutationError> {
        if let err = shortcut.validate() {
            return .failure(.invalidShortcut(err))
        }
        if snapshots.contains(where: { $0.id != id && $0.shortcut == shortcut }) {
            return .failure(.shortcutTaken)
        }
        guard let idx = snapshots.firstIndex(where: { $0.id == id }) else {
            return .failure(.notFound)
        }
        snapshots[idx].shortcut = shortcut
        persist()
        return .success(())
    }

    /// Replaces an existing snapshot's region/grid. No collision rule —
    /// multiple snapshots may legitimately share the same geometry as
    /// long as their shortcuts differ.
    @discardableResult
    func updateSpec(id: UUID, to spec: SnapSpec) -> Result<Void, MutationError> {
        guard let idx = snapshots.firstIndex(where: { $0.id == id }) else {
            return .failure(.notFound)
        }
        snapshots[idx].spec = spec
        persist()
        return .success(())
    }

    func remove(id: UUID) {
        snapshots.removeAll { $0.id == id }
        persist()
    }

    /// Bulk replace — used by the Import "Replace" flow.
    func replaceAll(_ newSnapshots: [Snapshot]) {
        snapshots = newSnapshots
        persist()
    }

    /// Bulk append, skipping any whose shortcut already exists.
    /// Returns counts for user feedback. Used by Import "Append".
    @discardableResult
    func append(_ incoming: [Snapshot]) -> (imported: Int, skipped: Int) {
        var imported = 0
        var skipped = 0
        for candidate in incoming {
            if snapshots.contains(where: { $0.shortcut == candidate.shortcut }) {
                skipped += 1
            } else {
                snapshots.append(candidate)
                imported += 1
            }
        }
        if imported > 0 { persist() }
        return (imported, skipped)
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.defaultsKey) else {
            return
        }
        do {
            snapshots = try JSONDecoder().decode([Snapshot].self, from: data)
            SnapshotLookupMirror.shared.store(snapshots)
        } catch {
            debugLog("[SnapshotStore] decode failed: \(error.localizedDescription)")
        }
    }

    private func persist() {
        SnapshotLookupMirror.shared.store(snapshots)
        do {
            let data = try JSONEncoder().encode(snapshots)
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        } catch {
            debugLog("[SnapshotStore] encode failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Errors

    enum MutationError: Error, Equatable {
        case shortcutTaken
        case notFound
        case invalidShortcut(ShortcutSpec.ValidationError)

        var message: String {
            switch self {
            case .shortcutTaken:          return "Another snapshot already uses this shortcut."
            case .notFound:               return "Snapshot not found."
            case .invalidShortcut(let e): return e.message
            }
        }
    }
}

