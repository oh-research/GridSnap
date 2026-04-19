import SwiftUI
import UniformTypeIdentifiers

/// Dedicated window for managing snapshots. Holds Recent + Saved lists
/// inside scrollable regions so the window stays short even when many
/// snaps accumulate, plus Export/Import buttons at the bottom. Drops
/// a `.sniq` file anywhere on the window to import.
struct SnapshotsWindowView: View {

    private let history = SnapHistory.shared
    private let store   = SnapshotStore.shared

    @State private var pendingError: String?
    @State private var isDropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            savedSection
            recentSection
            exportImportRow
            if let pendingError {
                Text(pendingError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(20)
        .frame(minWidth: 460, minHeight: 520)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers: providers)
        }
        .overlay(dropIndicator)
    }

    // MARK: - Drop handling

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first,
              provider.canLoadObject(ofClass: URL.self)
        else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            Task { @MainActor in
                SnapshotIO.importFile(at: url)
            }
        }
        return true
    }

    private var dropIndicator: some View {
        RoundedRectangle(cornerRadius: 10)
            .stroke(
                Color.accentColor,
                style: StrokeStyle(lineWidth: 2, dash: [6, 4])
            )
            .padding(6)
            .opacity(isDropTargeted ? 1 : 0)
            .animation(.easeInOut(duration: 0.12), value: isDropTargeted)
            .allowsHitTesting(false)
    }

    // MARK: - Saved

    private var savedSection: some View {
        GroupBox(label:
            Label("Saved · \(store.snapshots.count)", systemImage: "bookmark.fill")
                .labelStyle(.titleAndIcon)
        ) {
            if store.snapshots.isEmpty {
                EmptyStateRow(
                    systemImage: "square.dashed",
                    text: "Assign a shortcut to a recent snap below."
                )
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(store.snapshots) { snapshot in
                            SavedRow(snapshot: snapshot, onError: { pendingError = $0 })
                        }
                    }
                    .padding(.vertical, 2)
                }
                // 15 compact rows × ~30pt + spacing. Taller lists scroll
                // inside this window; expanded rows grow the list too.
                .frame(maxHeight: 510)
            }
        }
    }

    // MARK: - Recent

    private var recentSection: some View {
        GroupBox(label:
            Label("Recent · \(history.entries.count)", systemImage: "clock.arrow.circlepath")
                .labelStyle(.titleAndIcon)
        ) {
            if history.entries.isEmpty {
                EmptyStateRow(
                    systemImage: "hand.draw",
                    text: "Shift-drag a window to create your first snap."
                )
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(history.entries, id: \.self) { spec in
                            RecentRow(spec: spec, onError: { pendingError = $0 })
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: 220)
            }
        }
    }

    // MARK: - Export / Import

    private var exportImportRow: some View {
        HStack(spacing: 8) {
            Button {
                SnapshotIO.export()
            } label: {
                Label("Export…", systemImage: "square.and.arrow.up")
            }
            Button {
                SnapshotIO.importFromUser()
            } label: {
                Label("Import…", systemImage: "square.and.arrow.down")
            }
            Spacer()
        }
    }
}

// MARK: - Empty-state row

private struct EmptyStateRow: View {
    let systemImage: String
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(.tertiary)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
    }
}

// MARK: - Saved row

private struct SavedRow: View {
    let snapshot: Snapshot
    let onError: (String) -> Void

    @State private var hovering = false
    @State private var expanded = false
    @State private var editingShortcut = false
    @State private var draft: ShortcutSpec?

    var body: some View {
        VStack(spacing: 0) {
            header
            if expanded { editor }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(hovering || expanded
                      ? Color.accentColor.opacity(0.08)
                      : Color.secondary.opacity(0.05))
        )
        .onHover { hovering = $0 }
    }

    // MARK: - Collapsed header

    private var header: some View {
        HStack(spacing: 10) {
            Button {
                expanded.toggle()
            } label: {
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 12)
            }
            .buttonStyle(.plain)

            MiniGridBadge(spec: snapshot.spec)
            Text(snapshot.spec.summary)
                .font(.callout)
                .lineLimit(1)
            Spacer()
            shortcutControl
            Button {
                SnapshotStore.shared.remove(id: snapshot.id)
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(hovering ? .red : .secondary)
            }
            .buttonStyle(.borderless)
            .help("Remove snapshot")
        }
    }

    @ViewBuilder
    private var shortcutControl: some View {
        if editingShortcut {
            KeyRecorder(
                spec: $draft,
                placeholder: "Press keys…",
                autoStart: true,
                onCancel: { editingShortcut = false }
            )
            .onChange(of: draft) { _, new in
                guard let new else { return }
                let result = SnapshotStore.shared.updateShortcut(
                    id: snapshot.id, to: new
                )
                switch result {
                case .success:
                    editingShortcut = false
                case .failure(let err):
                    onError(err.message)
                    draft = nil
                    editingShortcut = false
                }
            }
        } else {
            Button {
                draft = snapshot.shortcut
                editingShortcut = true
            } label: {
                KeycapView(spec: snapshot.shortcut)
            }
            .buttonStyle(.plain)
            .help("Click to change shortcut")
        }
    }

    // MARK: - Expanded editor

    private var editor: some View {
        SnapshotEditForm(
            rows:   specBinding(\.rows),
            cols:   specBinding(\.cols),
            minRow: Binding(
                get: { snapshot.spec.minCell.row },
                set: { setCell(\.minCell, row: $0) }
            ),
            minCol: Binding(
                get: { snapshot.spec.minCell.col },
                set: { setCell(\.minCell, col: $0) }
            ),
            maxRow: Binding(
                get: { snapshot.spec.maxCell.row },
                set: { setCell(\.maxCell, row: $0) }
            ),
            maxCol: Binding(
                get: { snapshot.spec.maxCell.col },
                set: { setCell(\.maxCell, col: $0) }
            )
        )
        .padding(.top, 8)
        .padding(.leading, 28)
        .padding(.bottom, 4)
    }

    // MARK: - Bindings bridging to the store

    private func specBinding(_ keyPath: WritableKeyPath<SnapSpec, Int>) -> Binding<Int> {
        Binding(
            get: { snapshot.spec[keyPath: keyPath] },
            set: { new in
                var updated = snapshot.spec
                updated[keyPath: keyPath] = new
                SnapshotStore.shared.updateSpec(id: snapshot.id, to: updated)
            }
        )
    }

    private func setCell(
        _ which: WritableKeyPath<SnapSpec, GridCell>,
        row: Int? = nil,
        col: Int? = nil
    ) {
        var updated = snapshot.spec
        let current = updated[keyPath: which]
        updated[keyPath: which] = GridCell(
            row: row ?? current.row,
            col: col ?? current.col
        )
        SnapshotStore.shared.updateSpec(id: snapshot.id, to: updated)
    }
}

// MARK: - Recent row

private struct RecentRow: View {
    let spec: SnapSpec
    let onError: (String) -> Void

    @State private var draft: ShortcutSpec?
    @State private var hovering = false

    private var savedShortcut: ShortcutSpec? {
        SnapshotStore.shared.snapshots.first { $0.spec == spec }?.shortcut
    }

    var body: some View {
        HStack(spacing: 10) {
            MiniGridBadge(spec: spec)
            Text(spec.summary)
                .font(.callout)
                .lineLimit(1)
            Spacer()
            if let savedShortcut {
                HStack(spacing: 6) {
                    Text("Saved")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    KeycapView(spec: savedShortcut, isDimmed: true)
                }
            } else {
                KeyRecorder(spec: $draft, placeholder: "Assign shortcut…")
                    .onChange(of: draft) { _, new in
                        guard let new else { return }
                        let snap = Snapshot(spec: spec, shortcut: new)
                        if case .failure(let err) = SnapshotStore.shared.add(snap) {
                            onError(err.message)
                            draft = nil
                        }
                    }
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(hovering ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.05))
        )
        .onHover { hovering = $0 }
    }
}

// MARK: - Mini grid badge

/// Tiny 28×18 grid glyph that highlights the snapshot's region, giving
/// the user an at-a-glance shape without parsing the numeric summary.
private struct MiniGridBadge: View {
    let spec: SnapSpec

    var body: some View {
        Canvas { context, size in
            let cellW = size.width  / CGFloat(spec.cols)
            let cellH = size.height / CGFloat(spec.rows)

            let hx = CGFloat(spec.minCell.col) * cellW
            let hy = CGFloat(spec.minCell.row) * cellH
            let hw = CGFloat(spec.maxCell.col - spec.minCell.col + 1) * cellW
            let hh = CGFloat(spec.maxCell.row - spec.minCell.row + 1) * cellH
            context.fill(
                Path(CGRect(x: hx, y: hy, width: hw, height: hh).insetBy(dx: 1, dy: 1)),
                with: .color(.accentColor.opacity(0.55))
            )

            for c in 0...spec.cols {
                var path = Path()
                path.move(to: CGPoint(x: CGFloat(c) * cellW, y: 0))
                path.addLine(to: CGPoint(x: CGFloat(c) * cellW, y: size.height))
                context.stroke(path, with: .color(.secondary.opacity(0.45)), lineWidth: 0.5)
            }
            for r in 0...spec.rows {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: CGFloat(r) * cellH))
                path.addLine(to: CGPoint(x: size.width, y: CGFloat(r) * cellH))
                context.stroke(path, with: .color(.secondary.opacity(0.45)), lineWidth: 0.5)
            }
        }
        .frame(width: 28, height: 18)
    }
}
