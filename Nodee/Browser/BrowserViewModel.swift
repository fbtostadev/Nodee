//
//  BrowserViewModel.swift
//  Nodee
//
//  The brain of the file browser. Holds the navigation state for both surfaces —
//  List (current directory + in-place disclosure) and Columns (Miller drill-down)
//  — owns the selection and clipboard, and performs the file operations that make
//  Nodee a real Finder replacement (open, rename, new folder, trash, duplicate,
//  copy/paste). Like the canvas, it reads disk as the single source of truth and
//  reconciles on every FSEvents change so it never drifts out of sync.
//

import SwiftUI
import SwiftData
import AppKit

/// One visible line in the List surface: a file plus its indentation depth
/// relative to the current directory (0 = direct child).
struct BrowserRow: Identifiable, Hashable {
    let file: FileNode
    let depth: Int
    var id: URL { file.url }
}

@MainActor
@Observable
final class BrowserViewModel {
    private let container: ModelContainer
    private static let displayModeKey = "nodee.displayMode"

    /// Ceiling of navigation: the granted root (Home, or a favorite/volume's own
    /// bookmark) that contains `currentDirectory`. The breadcrumb anchors here and
    /// `navigateShallower()` stops here, so a walk up never escapes what the
    /// sandbox actually grants.
    private(set) var rootURL: URL?

    /// Active directory of the List surface; back/forward history walks this.
    private(set) var currentDirectory: URL?

    /// Which way the last List navigation moved, so the surface can slide its
    /// "page" in the matching direction (forward = into a folder / advance,
    /// backward = up to an ancestor / go back).
    enum NavDirection { case forward, backward }
    private(set) var navDirection: NavDirection = .forward
    /// Folders drilled into in the Columns surface (each adds one column). Column 0
    /// always lists the root; columnPath[i] backs column i+1.
    private(set) var columnPath: [URL] = []

    /// Selected items (multi-select for batch copy/duplicate/trash). Updating it
    /// refreshes the cached `selectedFile` so the preview never re-reads disk per
    /// view render.
    var selection: Set<URL> = [] { didSet { updateSelectedFile() } }
    /// Folders expanded in place in the List surface (disclosure triangles).
    private(set) var expanded: Set<URL> = []
    /// The row currently being renamed inline, if any.
    var renamingURL: URL?
    /// Set transiently when a rename fails so FileRowView can shake. Auto-cleared after 600 ms.
    var renameFailureURL: URL?

    /// Anchor for shift-range selection: the fixed end of the range.
    @ObservationIgnored private var anchorURL: URL?
    /// Moving end of a keyboard shift-range selection (the "cursor").
    @ObservationIgnored private var cursorURL: URL?
    /// Item a keyboard move wants brought into view; the surfaces observe it via
    /// ScrollViewReader. Reset to nil after the views consume it.
    var scrollTarget: URL?

    /// Precomputed visible structures, rebuilt on navigation / disk change so the
    /// views observe a stable snapshot instead of re-reading disk every frame.
    private(set) var rows: [BrowserRow] = []
    private(set) var columns: [[FileNode]] = []

    /// Whether the side Preview pane is currently visible when a file is selected.
    var isPreviewVisible: Bool = true
    /// Interactive physical offset of the Preview pane during a trackpad swipe.
    var previewPanOffset: CGFloat = 0

    /// In-app copy buffer for copy/paste. Observed so FileRowView shows the dashed indicator.
    private(set) var clipboard: [URL] = []

    /// Undo / redo stacks of file operations. A new operation clears redo, like
    /// every editor. Best-effort: replaying against a disk that changed underneath
    /// just skips what's gone.
    @ObservationIgnored private var undoStack: [FileAction] = []
    @ObservationIgnored private var redoStack: [FileAction] = []
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    /// Surfaces confirmations with an inline Undo for out-of-view operations
    /// (Trash, move into a pinned project). Wired up by PanelRootView — the VM
    /// isn't a View so it can't read it from the environment.
    @ObservationIgnored weak var toast: ToastCenter?

    var displayMode: DisplayMode {
        didSet {
            UserDefaults.standard.set(displayMode.rawValue, forKey: Self.displayModeKey)
            rebuild() // build the surface we just switched to
            startWatching() // the two surfaces watch different directories
        }
    }

    /// Cached file shown in the side preview / final column: kept in sync with
    /// `selection` so reads never touch disk during view rendering.
    private(set) var selectedFile: FileNode?

    // History stack for back/forward (List surface).
    @ObservationIgnored private var history: [URL] = []
    @ObservationIgnored private var historyIndex = -1

    @ObservationIgnored private var watcher: DirectoryWatcher?

    init(container: ModelContainer) {
        self.container = container
        let raw = UserDefaults.standard.string(forKey: Self.displayModeKey)
        self.displayMode = raw.flatMap(DisplayMode.init(rawValue:)) ?? .list
    }

    // MARK: - Derived state

    /// Directory new files land in (new folder, paste): the active spot per mode.
    var activeDirectory: URL? {
        switch displayMode {
        case .list:    return currentDirectory
        case .columns: return columnPath.last ?? rootURL
        }
    }

    /// Recompute the cached `selectedFile`: a single existing selection, else nil.
    private func updateSelectedFile() {
        guard selection.count == 1, let url = selection.first,
              FileSystemService.exists(url) else { selectedFile = nil; return }
        
        let newFile = FileNode(url: url)
        if selectedFile?.url != newFile.url {
            selectedFile = newFile
            isPreviewVisible = true
        }
    }

    /// Linear URL order of the surface the keyboard / range-select acts on.
    private var activeOrder: [URL] {
        switch displayMode {
        case .list:    return rows.map(\.file.url)
        case .columns: return (columns.last ?? []).map(\.url)
        }
    }

    var canGoBack: Bool { historyIndex > 0 }
    var canGoForward: Bool { historyIndex < history.count - 1 }

    /// Root → current directory chain for the breadcrumb (List surface).
    var breadcrumb: [FileNode] {
        guard let root = rootURL, let current = currentDirectory else { return [] }
        var urls: [URL] = [root]
        let rootCount = root.standardizedFileURL.pathComponents.count
        let currentComponents = current.standardizedFileURL.pathComponents
        if currentComponents.count > rootCount {
            var url = root
            for component in currentComponents[rootCount...] {
                url.appendPathComponent(component)
                urls.append(url)
            }
        }
        return urls.map(FileNode.init)
    }

    // MARK: - Jump to a location

    /// Jump to `url` (a sidebar Location or Favorite), bounded by `accessRoot` —
    /// the granted root that contains it. A fresh context: history, columns and
    /// undo all reset, as if opening that place anew. In Columns the drill path is
    /// rebuilt from the access root down to `url` so both surfaces stay coherent.
    func go(to url: URL, accessRoot: URL) {
        // A sidebar jump is a dry cut, not a page slide.
        navDirection = .forward
        self.rootURL = accessRoot
        self.currentDirectory = url
        self.columnPath = columnPath(from: accessRoot, to: url)
        self.selection = []
        self.expanded = []
        self.renamingURL = nil
        self.history = [url]
        self.historyIndex = 0
        self.undoStack = []
        self.redoStack = []

        rebuild()
        startWatching()
        persistCurrentDirectory()
    }

    func clear() {
        watcher?.stop(); watcher = nil
        rootURL = nil; currentDirectory = nil
        columnPath = []; selection = []; expanded = []; renamingURL = nil
        rows = []; columns = []
        history = []; historyIndex = -1
        undoStack = []; redoStack = []
    }

    // MARK: - Navigation (List surface)

    /// Navigate the List surface into `url`, recording history unless replaying it.
    /// `direction` overrides the page-slide direction; when nil it's inferred from
    /// path depth (deeper = forward, shallower = backward).
    func navigate(to url: URL, recordHistory: Bool = true, direction: NavDirection? = nil) {
        if let direction {
            navDirection = direction
        } else if let old = currentDirectory {
            let oldDepth = old.standardizedFileURL.pathComponents.count
            let newDepth = url.standardizedFileURL.pathComponents.count
            navDirection = newDepth < oldDepth ? .backward : .forward
        }
        currentDirectory = url
        selection = []
        if recordHistory {
            if historyIndex < history.count - 1 {
                history.removeSubrange((historyIndex + 1)...)
            }
            history.append(url)
            historyIndex = history.count - 1
        }
        rebuild()
        startWatching()
        persistCurrentDirectory()
    }

    func goBack() {
        guard canGoBack else { return }
        historyIndex -= 1
        navigate(to: history[historyIndex], recordHistory: false, direction: .backward)
    }

    func goForward() {
        guard canGoForward else { return }
        historyIndex += 1
        navigate(to: history[historyIndex], recordHistory: false, direction: .forward)
    }

    /// Enter a folder (double-click in list / breadcrumb tap): changes the current
    /// directory. No-op for files.
    func enter(_ file: FileNode) {
        guard file.isDirectory else { return }
        navigate(to: file.url)
    }

    /// Two-finger horizontal navigation (List surface only): step *into* the
    /// selected folder. Mirrors the rightward drill of the Columns surface.
    /// Returns `true` when navigation actually happened, so callers can gate
    /// feedback (e.g. the navigation glyph) on a real move.
    @discardableResult
    func navigateDeeper() -> Bool {
        guard displayMode == .list, let file = selectedFile, file.isDirectory else { return false }
        navigate(to: file.url)
        return true
    }

    /// Two-finger horizontal navigation (List surface only): step *up* to the
    /// parent directory, bounded by the access root so a swipe never escapes what
    /// the sandbox grants. Returns `true` when navigation actually happened.
    @discardableResult
    func navigateShallower() -> Bool {
        guard displayMode == .list, let current = currentDirectory, let root = rootURL else { return false }
        guard current.standardizedFileURL != root.standardizedFileURL else { return false }
        navigate(to: current.deletingLastPathComponent())
        return true
    }

    // MARK: - Selection & disclosure

    /// Click selection. `extending` (⌘-click) toggles the item; otherwise it
    /// replaces the selection. Either way the clicked item becomes the anchor for
    /// a subsequent shift-range select.
    func select(_ url: URL, extending: Bool = false) {
        if extending {
            if selection.contains(url) { selection.remove(url) } else { selection.insert(url) }
        } else {
            selection = [url]
        }
        anchorURL = url
        cursorURL = url
    }

    /// Shift-click: select the contiguous run from the anchor to `url` on the
    /// active surface. Falls back to a plain select when there's no usable anchor.
    func selectRange(to url: URL) {
        let order = activeOrder
        guard let anchor = anchorURL ?? selection.first,
              let a = order.firstIndex(of: anchor),
              let b = order.firstIndex(of: url) else { select(url); return }
        selection = Set(order[min(a, b)...max(a, b)])
        cursorURL = url
        // Anchor stays put so the range can be grown/shrunk with further shifts.
    }

    /// Arrow up/down: move a single selection by `delta` along the active surface.
    func moveSelection(by delta: Int) {
        let order = activeOrder
        guard !order.isEmpty else { return }
        let current = selection.count == 1 ? selection.first.flatMap(order.firstIndex(of:)) : nil
        let next: Int
        if let i = current { next = min(max(i + delta, 0), order.count - 1) }
        else { next = delta > 0 ? 0 : order.count - 1 }
        let url = order[next]
        selection = [url]
        anchorURL = url
        cursorURL = url
        scrollTarget = url
    }

    /// Shift + arrow up/down: grow or shrink the selection by moving the cursor end
    /// while the anchor stays fixed, like a Finder list. Starts a range from the
    /// current single selection when none is active yet.
    func extendSelection(by delta: Int) {
        let order = activeOrder
        guard !order.isEmpty else { return }
        let anchor = anchorURL ?? selection.first ?? order[0]
        guard let anchorIdx = order.firstIndex(of: anchor) else { moveSelection(by: delta); return }
        let cursorIdx = (cursorURL ?? selection.first).flatMap(order.firstIndex(of:)) ?? anchorIdx
        let nextIdx = min(max(cursorIdx + delta, 0), order.count - 1)
        anchorURL = anchor
        cursorURL = order[nextIdx]
        selection = Set(order[min(anchorIdx, nextIdx)...max(anchorIdx, nextIdx)])
        scrollTarget = order[nextIdx]
    }

    /// Right arrow: expand the selected folder (List) or drill into it (Columns).
    func drillSelection() {
        switch displayMode {
        case .list:
            guard let url = selection.first,
                  let row = rows.first(where: { $0.file.url == url }), row.file.isDirectory else { return }
            if !expanded.contains(url) { toggleExpanded(row.file) } else { moveSelection(by: 1) }
        case .columns:
            guard let url = selection.first,
                  let file = (columns.last ?? []).first(where: { $0.url == url }), file.isDirectory else { return }
            selectInColumn(url, column: max(columns.count - 1, 0))
        }
    }

    /// Left arrow: collapse the selected folder / step to its parent (List) or
    /// back out one column (Columns).
    func undrillSelection() {
        switch displayMode {
        case .list:
            guard let url = selection.first else { return }
            if let row = rows.first(where: { $0.file.url == url }), row.file.isDirectory, expanded.contains(url) {
                toggleExpanded(row.file)
            } else {
                let parent = url.deletingLastPathComponent()
                guard rows.contains(where: { $0.file.url == parent }) else { return }
                selection = [parent]; anchorURL = parent; scrollTarget = parent
            }
        case .columns:
            guard let parent = columnPath.last else { return }
            columnPath.removeLast()
            selection = [parent]; anchorURL = parent
            rebuildColumns()
            startWatching()
            persistCurrentDirectory()
        }
    }

    func toggleExpanded(_ file: FileNode) {
        guard file.isDirectory else { return }
        if expanded.contains(file.url) { expanded.remove(file.url) } else { expanded.insert(file.url) }
        rebuild()
    }

    func isExpanded(_ url: URL) -> Bool { expanded.contains(url) }

    // MARK: - Navigation (Columns surface)

    /// Select an item in display column `column`. Truncates any deeper drill, and
    /// opens a new column when the item is a folder.
    func selectInColumn(_ url: URL, column: Int) {
        if column < columnPath.count {
            columnPath.removeSubrange(column...)
        }
        // Mirror FileNode: bundles are directories on disk but navigate like files.
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        let isNavigableDir = (values?.isDirectory ?? false) && !(values?.isPackage ?? false)
        if isNavigableDir { columnPath.append(url) }
        selection = [url]
        rebuildColumns()
        startWatching()
        persistCurrentDirectory()
    }

    // MARK: - File operations

    func open(_ file: FileNode) {
        if file.isDirectory {
            displayMode == .columns ? selectInColumn(file.url, column: columnDepth(of: file.url)) : enter(file)
        } else {
            FileSystemService.open(file.url)
        }
    }

    func newFolder() {
        guard let dir = activeDirectory, let created = FileSystemService.createFolder(in: dir) else { return }
        record(.create(urls: [created]))
        rebuild()
        selection = [created]
        renamingURL = created // drop straight into inline rename, like the Finder
    }

    func beginRename(_ url: URL) { renamingURL = url }

    func commitRename(_ url: URL, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        // Empty or identical name → silent cancel, not an error.
        guard !trimmed.isEmpty, trimmed != url.lastPathComponent else {
            renamingURL = nil
            return
        }
        guard let newURL = FileSystemService.rename(url, to: trimmed) else {
            // Keep the field open; FileRowView shakes via renameFailureURL.
            renameFailureURL = url
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(600))
                self?.renameFailureURL = nil
            }
            return
        }
        renamingURL = nil
        record(.move(items: [(from: url, to: newURL)]))
        if selection.contains(url) { selection.remove(url); selection.insert(newURL) }
        remapPaths(from: url, to: newURL)
        rebuild()
    }

    func cancelRename() {
        renamingURL = nil
        renameFailureURL = nil
    }

    func trashSelection() {
        let trashed = FileSystemService.moveToTrash(Array(selection))
        guard !trashed.isEmpty else { return }
        record(.trash(items: trashed))
        selection.subtract(trashed.map(\.original))
        rebuild()
        let n = trashed.count
        let sourceFolder = trashed.first?.original.deletingLastPathComponent().lastPathComponent ?? ""
        let ctx = ToastContext(kind: .trashed,
                              fileNames: trashed.map { $0.original.lastPathComponent },
                              sourceFolder: sourceFolder,
                              destinationFolder: nil,
                              destinationURL: nil)
        toast?.show(n == 1 ? "1 item na Lixeira" : "\(n) itens na Lixeira",
                    actionLabel: "Desfazer",
                    context: ctx,
                    action: { [weak self] in self?.undo() })
    }

    func duplicateSelection() {
        var copies: Set<URL> = []
        for url in selection {
            if let copy = FileSystemService.duplicate(url) { copies.insert(copy) }
        }
        guard !copies.isEmpty else { return }
        record(.create(urls: Array(copies)))
        rebuild()
        selection = copies
    }

    func copySelection() { clipboard = Array(selection) }

    func paste() {
        guard let dir = activeDirectory, !clipboard.isEmpty else { return }
        let pasted = FileSystemService.copy(clipboard, into: dir)
        if pasted.isEmpty {
            toast?.show("Falha ao colar", duration: 2, isError: true)
            return
        }
        record(.create(urls: pasted))
        rebuild()
        selection = Set(pasted)
        let n = pasted.count
        toast?.show(n == 1 ? "1 item colado" : "\(n) itens colados",
                    actionLabel: "Desfazer", duration: 3,
                    action: { [weak self] in self?.undo() })
    }

    /// Move `source` into `folder` on disk (drag-and-drop). FSEvents reconciles.
    func move(_ source: URL, into folder: URL) {
        move([source], into: folder)
    }

    /// Move (or copy, holding ⌥) a batch into `folder`, recorded as one undoable
    /// step so the whole drop reverts together. When the destination sits outside
    /// the visible tree (e.g. a drop onto a pinned project), a toast confirms it.
    func move(_ sources: [URL], into folder: URL, copy: Bool = false) {
        if copy {
            let made = FileSystemService.copy(sources, into: folder)
            if made.isEmpty {
                toast?.show("Não foi possível copiar", duration: 2.5, isError: true)
                return
            }
            record(.create(urls: made))
            rebuild()
            confirmOutOfView(made, from: sources, into: folder, copied: true)
            return
        }

        var pairs: [(from: URL, to: URL)] = []
        for source in sources {
            guard let newURL = FileSystemService.move(source, into: folder) else { continue }
            if selection.contains(source) { selection.remove(source); selection.insert(newURL) }
            remapPaths(from: source, to: newURL)
            pairs.append((from: source, to: newURL))
        }
        if pairs.isEmpty {
            toast?.show("Não foi possível mover", duration: 2.5, isError: true)
            return
        }
        record(.move(items: pairs))
        rebuild()
        confirmOutOfView(pairs.map(\.to), from: pairs.map(\.from), into: folder, copied: false)
    }

    /// Toast a move/copy whose result isn't visible in the current surface (the
    /// destination folder isn't part of the open tree). Moves within view stay
    /// silent — their result is already on screen.
    private func confirmOutOfView(_ results: [URL], from sources: [URL], into folder: URL, copied: Bool) {
        let folderURL = folder.standardizedFileURL
        // List: check rows (which cover expanded subfolders) and the current directory.
        // Columns: check the drilled path — only those directories' contents are visible
        // as columns. Do NOT check `columns` items directly; `columns` is stale when the
        // user switches modes and `folder` might appear as a listed item (e.g. Desktop as
        // a child of Home) even when its *contents* aren't the active column.
        let visible: Bool
        switch displayMode {
        case .list:
            visible = rows.contains { $0.file.url.deletingLastPathComponent().standardizedFileURL == folderURL }
                || currentDirectory?.standardizedFileURL == folderURL
        case .columns:
            let drilled = ([rootURL].compactMap { $0 } + columnPath).map { $0.standardizedFileURL }
            visible = drilled.contains(folderURL)
        }
        guard !visible else { return }
        let verb = copied ? "Copiado" : "Movido"
        // Source folder = the directory the file actually came from.
        let sourceFolder = sources.first?.deletingLastPathComponent().lastPathComponent ?? ""
        let movedURLs = results
        let ctx = ToastContext(kind: copied ? .copied : .moved,
                              fileNames: results.map { $0.lastPathComponent },
                              sourceFolder: sourceFolder,
                              destinationFolder: folder.lastPathComponent,
                              destinationURL: folder)
        toast?.show("\(verb) para \(folder.lastPathComponent)",
                    actionLabel: "Desfazer",
                    context: ctx,
                    action: { [weak self] in self?.undo() },
                    navigationAction: { [weak self] in
                        guard let self else { return }
                        self.navigate(to: folder)
                        // Pre-select the moved/copied files so the user lands with them highlighted.
                        self.selection = Set(movedURLs)
                    })
    }

    func newFile() {
        guard let dir = activeDirectory, let created = FileSystemService.createFile(in: dir) else { return }
        record(.create(urls: [created]))
        rebuild()
        selection = [created]
        renamingURL = created // straight into inline rename, like New Folder
    }

    // MARK: - Undo / redo

    private func record(_ action: FileAction) {
        undoStack.append(action)
        redoStack.removeAll()
    }

    func undo() {
        guard let action = undoStack.popLast() else { return }
        guard let redo = action.reverted() else {
            toast?.show("Não foi possível desfazer", duration: 2.5, isError: true)
            return
        }
        redoStack.append(redo)
        reselect(redo.resultingURLs)
        rebuild()
        toast?.show(undoDescription(for: action), duration: 2)
    }

    func redo() {
        guard let action = redoStack.popLast() else { return }
        guard let undo = action.reverted() else {
            toast?.show("Não foi possível refazer", duration: 2.5, isError: true)
            return
        }
        undoStack.append(undo)
        reselect(undo.resultingURLs)
        rebuild()
        toast?.show(redoDescription(for: action), duration: 2)
    }

    private func undoDescription(for action: FileAction) -> String {
        switch action {
        case .move(let items):
            return items.count == 1
                ? "Desfeito: mover \(items[0].from.lastPathComponent)"
                : "Desfeito: mover \(items.count) itens"
        case .trash(let items):
            return items.count == 1
                ? "Desfeito: enviar \(items[0].original.lastPathComponent) para Lixeira"
                : "Desfeito: \(items.count) itens restaurados da Lixeira"
        case .create(let urls):
            return urls.count == 1
                ? "Desfeito: criar \(urls[0].lastPathComponent)"
                : "Desfeito: criar \(urls.count) itens"
        }
    }

    private func redoDescription(for action: FileAction) -> String {
        undoDescription(for: action).replacingOccurrences(of: "Desfeito:", with: "Refeito:")
    }

    /// After an undo/redo, select the items it left on disk that are reachable in
    /// the current surface (restored-to-Trash URLs simply won't match — fine).
    private func reselect(_ urls: [URL]) {
        let reachable = Set(urls.filter(FileSystemService.exists))
        if !reachable.isEmpty { selection = reachable }
    }

    /// Reveal the selection (or the active directory if nothing is selected) in the
    /// Finder — the deliberate hand-off for operations Nodee doesn't own.
    func revealInFinder() {
        let urls = selection.isEmpty ? [activeDirectory].compactMap { $0 } : Array(selection)
        FileSystemService.revealInFinder(urls)
    }

    /// Copy the POSIX path(s) of the selection to the pasteboard (one per line).
    func copyPath() {
        let urls = selection.map(\.path).sorted()
        guard !urls.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(urls.joined(separator: "\n"), forType: .string)
        toast?.show(urls.count == 1 ? "Caminho copiado" : "\(urls.count) caminhos copiados",
                    duration: 1.6)
    }

    /// Copy the current directory's POSIX path to the pasteboard — the toolbar's
    /// "copy the URL" affordance, mirroring a browser's address-bar copy button.
    func copyDirectoryPath() {
        guard let dir = activeDirectory else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(dir.path, forType: .string)
        toast?.show("Caminho copiado", duration: 1.6)
    }

    // MARK: - Disk reconciliation

    private func reconcile() {
        guard let root = rootURL else { return }
        if !FileSystemService.exists(root) { clear(); return }
        // Drop navigation that points at now-missing folders.
        var watchedDirChanged = false
        if let current = currentDirectory, !FileSystemService.exists(current) {
            currentDirectory = root
            watchedDirChanged = true
        }
        let prunedPath = prunedColumnPath()
        if prunedPath.count != columnPath.count { watchedDirChanged = true }
        columnPath = prunedPath
        selection = selection.filter(FileSystemService.exists)
        rebuild()
        // The directory we were watching vanished — re-point at where we landed.
        if watchedDirChanged { startWatching() }
    }

    // MARK: - Rebuilding visible structures

    /// Rebuild only the surface in view; the other is rebuilt lazily when
    /// `displayMode` flips. Keeps a disk change from re-reading both List and
    /// Columns (and every drilled column) on every FSEvents tick.
    private func rebuild() {
        switch displayMode {
        case .list:    rebuildRows()
        case .columns: rebuildColumns()
        }
    }

    private func rebuildRows() {
        guard let dir = currentDirectory else { rows = []; return }
        var out: [BrowserRow] = []
        func walk(_ url: URL, depth: Int) {
            for child in FileSystemService.children(of: url) {
                out.append(BrowserRow(file: child, depth: depth))
                if child.isDirectory && expanded.contains(child.url) {
                    walk(child.url, depth: depth + 1)
                }
            }
        }
        walk(dir, depth: 0)
        rows = out
    }

    private func rebuildColumns() {
        guard let root = rootURL else { columns = []; return }
        let directories = [root] + prunedColumnPath()
        columns = directories.map { FileSystemService.children(of: $0) }
    }

    // MARK: - Helpers

    /// Display-column index whose listing contains `url` (its parent's depth).
    private func columnDepth(of url: URL) -> Int {
        let parent = url.deletingLastPathComponent().standardizedFileURL
        if let idx = columnPath.firstIndex(where: { $0.standardizedFileURL == parent }) {
            return idx + 1
        }
        return 0 // parent is the root
    }

    private func prunedColumnPath() -> [URL] {
        var pruned: [URL] = []
        for url in columnPath {
            guard FileSystemService.exists(url) else { break }
            pruned.append(url)
        }
        return pruned
    }

    /// After a rename/move, rewrite expanded/columnPath/currentDirectory entries
    /// that lived under the old URL so open folders stay open.
    private func remapPaths(from old: URL, to new: URL) {
        let oldPath = old.standardizedFileURL.path
        func remap(_ url: URL) -> URL {
            let path = url.standardizedFileURL.path
            if path == oldPath { return new }
            if path.hasPrefix(oldPath + "/") {
                let suffix = String(path.dropFirst(oldPath.count))
                return URL(fileURLWithPath: new.standardizedFileURL.path + suffix)
            }
            return url
        }
        expanded = Set(expanded.map(remap))
        columnPath = columnPath.map(remap)
        // The back/forward stack also holds URLs that may live under the renamed
        // folder; remapping keeps navigation history pointing at live paths.
        history = history.map(remap)
        if let current = currentDirectory { currentDirectory = remap(current) }
    }

    // MARK: - Watching & persistence

    /// (Re)point the FSEvents watcher at the directory currently in view — the
    /// List's `currentDirectory` (recursive, so expanded subfolders are covered)
    /// or the Columns' last drilled folder. Watching only the visible directory
    /// keeps us off a recursive stream over the whole Home grant.
    private func startWatching() {
        watcher?.stop(); watcher = nil
        let target = displayMode == .columns ? (columnPath.last ?? rootURL) : currentDirectory
        guard let target else { return }
        let w = DirectoryWatcher(url: target) { [weak self] in self?.reconcile() }
        w.start()
        watcher = w
    }

    /// The drill chain (each entry backs one column) from `root` down to `url`,
    /// so jumping to a nested Location lands Columns on the right path.
    private func columnPath(from root: URL, to url: URL) -> [URL] {
        let rootComps = root.standardizedFileURL.pathComponents
        let urlComps = url.standardizedFileURL.pathComponents
        guard urlComps.count > rootComps.count,
              Array(urlComps.prefix(rootComps.count)) == rootComps else { return [] }
        var path: [URL] = []
        var u = root
        for comp in urlComps[rootComps.count...] {
            u.appendPathComponent(comp)
            path.append(u)
        }
        return path
    }

    /// Persist the active directory (single-row upsert) so reopening the panel
    /// restores where we left off. Best-effort; failures are non-fatal.
    private func persistCurrentDirectory() {
        guard let dir = activeDirectory else { return }
        let context = container.mainContext
        // Newest row first, so the single-row upsert stays robust even if a
        // duplicate ever slips in — we always rewrite the most recent one.
        let existing = try? context.fetch(
            FetchDescriptor<BrowserState>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        )
        if let state = existing?.first {
            state.directoryPath = dir.standardizedFileURL.path
            state.updatedAt = Date()
        } else {
            context.insert(BrowserState(directoryPath: dir.standardizedFileURL.path))
        }
        try? context.save()
    }

    /// The last persisted directory, if any (resolved by the panel on restore).
    func lastVisitedDirectory() -> URL? {
        let context = container.mainContext
        // Most recently updated row wins, matching the upsert above.
        let descriptor = FetchDescriptor<BrowserState>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        guard let state = try? context.fetch(descriptor).first else { return nil }
        return URL(fileURLWithPath: state.directoryPath)
    }
}
