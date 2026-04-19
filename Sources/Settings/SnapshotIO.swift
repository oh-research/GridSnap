import Cocoa

/// Import/export glue between `SnapshotStore` and user-picked `.sniq`
/// files. Presents `NSSavePanel` / `NSOpenPanel` with a remembered last
/// directory (default `~/Documents/Sniq/`) and, on import, prompts the
/// user to choose Append vs Replace.
@MainActor
enum SnapshotIO {

    private static let lastDirectoryKey = "snapshotIO.lastDirectory"

    // MARK: - Export

    static func export() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "snapshots-\(dateStamp()).sniq"
        panel.directoryURL = initialDirectory()
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        rememberDirectory(url.deletingLastPathComponent())

        let text = SnapshotFile.serialize(SnapshotStore.shared.snapshots)
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            showAlert(title: "Export failed", message: error.localizedDescription)
        }
    }

    // MARK: - Import

    static func importFromUser() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.directoryURL = initialDirectory()

        guard panel.runModal() == .OK, let url = panel.url else { return }
        importFile(at: url)
    }

    /// Shared entry for "the user gave us this `.sniq` file" — used by
    /// both the Import… panel and the drag-and-drop handler on the
    /// Snapshots window.
    static func importFile(at url: URL) {
        guard url.pathExtension.lowercased() == "sniq" else {
            showAlert(
                title: "Unsupported file",
                message: "Only .sniq files can be imported."
            )
            return
        }
        rememberDirectory(url.deletingLastPathComponent())

        let text: String
        do {
            text = try String(contentsOf: url, encoding: .utf8)
        } catch {
            showAlert(title: "Import failed", message: error.localizedDescription)
            return
        }
        let result = SnapshotFile.parse(text)
        promptApply(result: result, filename: url.lastPathComponent)
    }

    // MARK: - Apply prompt

    private static func promptApply(result: SnapshotFile.ParseResult, filename: String) {
        if result.snapshots.isEmpty {
            let detail = result.issues.isEmpty
                ? "No snapshots were found in \(filename)."
                : issueSummary(result.issues)
            showAlert(title: "Nothing to import", message: detail)
            return
        }

        let alert = NSAlert()
        alert.messageText = "Import \(result.snapshots.count) snapshots from \(filename)?"
        alert.informativeText = """
            Append adds only snapshots whose shortcut is not already in use.
            Replace overwrites all currently-saved snapshots.
            """
        alert.addButton(withTitle: "Append")
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            let stats = SnapshotStore.shared.append(result.snapshots)
            reportOutcome(imported: stats.imported, skipped: stats.skipped, issues: result.issues)
        case .alertSecondButtonReturn:
            SnapshotStore.shared.replaceAll(result.snapshots)
            reportOutcome(
                imported: result.snapshots.count,
                skipped: 0,
                issues: result.issues
            )
        default:
            return
        }
    }

    private static func reportOutcome(
        imported: Int, skipped: Int, issues: [SnapshotFile.Issue]
    ) {
        var lines: [String] = []
        lines.append("\(imported) imported" + (skipped > 0 ? ", \(skipped) skipped" : ""))
        if !issues.isEmpty { lines.append(issueSummary(issues)) }
        showAlert(title: "Import complete", message: lines.joined(separator: "\n\n"))
    }

    private static func issueSummary(_ issues: [SnapshotFile.Issue]) -> String {
        let head = issues.prefix(5).map { "• line \($0.line): \($0.message)" }.joined(separator: "\n")
        if issues.count <= 5 { return head }
        return head + "\n• … and \(issues.count - 5) more"
    }

    // MARK: - Directory memory

    private static func initialDirectory() -> URL {
        if let path = UserDefaults.standard.string(forKey: lastDirectoryKey),
           FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return defaultDirectory()
    }

    private static func rememberDirectory(_ url: URL) {
        UserDefaults.standard.set(url.path, forKey: lastDirectoryKey)
    }

    private static func defaultDirectory() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return docs.appendingPathComponent("Sniq", isDirectory: true)
    }

    // MARK: - Misc

    private static func dateStamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private static func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}
