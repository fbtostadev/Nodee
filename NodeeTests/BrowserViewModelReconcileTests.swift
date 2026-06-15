//
//  BrowserViewModelReconcileTests.swift
//  NodeeTests
//
//  Unit tests for BrowserViewModel's navigation-state reconciliation helpers:
//  columnPath(from:to:), prunedColumnPath(), and remapPaths(from:to:). These are
//  the pieces that keep List/Columns navigation coherent after a rename/move/delete
//  on disk. They were `private`; relaxed to `internal` (module-private) purely to
//  make them testable via `@testable import Nodee` — see the comments at each
//  declaration in BrowserViewModel.swift. No production behavior changed.
//
//  State is driven through the public `go(to:accessRoot:)` entry point and exercised
//  against a real temporary directory tree, then the helpers are called directly.
//

import XCTest
import SwiftData
@testable import Nodee

@MainActor
final class BrowserViewModelReconcileTests: XCTestCase {
    private var root: URL!
    private var container: ModelContainer!
    /// Created VMs are deliberately leaked here for the lifetime of the test process.
    /// BrowserViewModel is a `@MainActor @Observable` whose implicit deinit hops
    /// executors (`swift_task_deinitOnExecutorImpl` → `StopLookupScope` dtor); on this
    /// toolchain that hop trips a libmalloc double-free whenever the object actually
    /// deallocates. Never releasing them means deinit never runs, so the runtime bug
    /// can't fire. A handful of small VMs leaked across a test run is harmless and
    /// keeps the suite green; the logic under test (the reconciliation helpers) is
    /// fully exercised before the leak. Static so removeAll/teardown never frees them.
    private static var leakedVMs: [BrowserViewModel] = []

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("NodeeTests-VM-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        // In-memory SwiftData container with the same schema the app uses for the
        // models BrowserViewModel touches (BrowserState upserts on navigation).
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: PinnedProject.self, BrowserState.self, configurations: config)
    }

    override func tearDownWithError() throws {
        // Stop the VMs' FSEvents watchers (cheap, doesn't free the VM). We keep the
        // VM objects alive process-wide (see `leakedVMs`) to dodge the deinit crash.
        for vm in Self.leakedVMs { vm.clear() }
        if let root, FileManager.default.fileExists(atPath: root.path) {
            try FileManager.default.removeItem(at: root)
        }
        root = nil
        container = nil
    }

    @discardableResult
    private func makeDir(_ path: String) throws -> URL {
        let url = root.appendingPathComponent(path, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeVM() -> BrowserViewModel {
        let vm = BrowserViewModel(container: container)
        Self.leakedVMs.append(vm) // deliberately leaked; never deallocated (see above)
        return vm
    }

    // MARK: - columnPath(from:to:)

    func testColumnPathBuildsDrillChain() throws {
        let vm = makeVM()
        let a = root.appendingPathComponent("a")
        let b = a.appendingPathComponent("b")
        let c = b.appendingPathComponent("c")
        let chain = vm.columnPath(from: root, to: c)
        XCTAssertEqual(chain.map(\.lastPathComponent), ["a", "b", "c"])
    }

    func testColumnPathEmptyWhenUrlIsRoot() throws {
        let vm = makeVM()
        XCTAssertEqual(vm.columnPath(from: root, to: root), [])
    }

    func testColumnPathEmptyWhenUrlOutsideRoot() throws {
        let vm = makeVM()
        let outside = URL(fileURLWithPath: "/etc/hosts")
        XCTAssertEqual(vm.columnPath(from: root, to: outside), [])
    }

    // MARK: - prunedColumnPath()

    func testPrunedColumnPathStopsAtFirstMissing() throws {
        let a = try makeDir("a")
        let b = try makeDir("a/b")
        let c = b.appendingPathComponent("c", isDirectory: true) // never created on disk
        let vm = makeVM()
        // go(to:accessRoot:) sets columnPath = chain from root to the target folder.
        vm.go(to: c, accessRoot: root)
        XCTAssertEqual(vm.columnPath.map(\.lastPathComponent), ["a", "b", "c"])
        // c doesn't exist → pruned chain stops before it.
        XCTAssertEqual(vm.prunedColumnPath().map(\.lastPathComponent), ["a", "b"])
        _ = a
    }

    func testPrunedColumnPathKeepsFullChainWhenAllExist() throws {
        try makeDir("a")
        let b = try makeDir("a/b")
        let vm = makeVM()
        vm.go(to: b, accessRoot: root)
        XCTAssertEqual(vm.prunedColumnPath().map(\.lastPathComponent), ["a", "b"])
    }

    // MARK: - remapPaths(from:to:)

    func testRemapPathsRewritesCurrentDirectoryAndColumnPath() throws {
        try makeDir("old")
        let oldChild = try makeDir("old/child")
        let vm = makeVM()
        vm.go(to: oldChild, accessRoot: root)
        XCTAssertEqual(vm.currentDirectory?.lastPathComponent, "child")
        XCTAssertEqual(vm.columnPath.map(\.lastPathComponent), ["old", "child"])

        // Simulate "old" renamed to "renamed" on disk.
        let oldDir = root.appendingPathComponent("old")
        let newDir = root.appendingPathComponent("renamed")
        vm.remapPaths(from: oldDir, to: newDir)

        // The descendant currentDirectory follows the rename...
        XCTAssertEqual(
            vm.currentDirectory?.standardizedFileURL,
            newDir.appendingPathComponent("child").standardizedFileURL
        )
        // ...and so does every entry in the drill chain.
        XCTAssertEqual(vm.columnPath.map(\.lastPathComponent), ["renamed", "child"])
        XCTAssertEqual(
            vm.columnPath.first?.standardizedFileURL,
            newDir.standardizedFileURL
        )
    }

    func testRemapPathsLeavesUnrelatedPathsUntouched() throws {
        try makeDir("keep")
        let keepChild = try makeDir("keep/inner")
        let vm = makeVM()
        vm.go(to: keepChild, accessRoot: root)

        // Rename a sibling that isn't on the current path.
        let unrelatedOld = root.appendingPathComponent("other")
        let unrelatedNew = root.appendingPathComponent("other-renamed")
        vm.remapPaths(from: unrelatedOld, to: unrelatedNew)

        XCTAssertEqual(vm.columnPath.map(\.lastPathComponent), ["keep", "inner"])
        XCTAssertEqual(vm.currentDirectory?.lastPathComponent, "inner")
    }
}
