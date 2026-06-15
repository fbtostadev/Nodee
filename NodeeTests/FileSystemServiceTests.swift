//
//  FileSystemServiceTests.swift
//  NodeeTests
//
//  Unit tests for FileSystemService's pure disk logic, exercised against a real
//  temporary directory: name-collision resolution (the "name 2.ext" scheme used
//  by copy/duplicate/rename/createFolder), children(of:) ordering, exists(_:),
//  and relativePath(of:root:).
//

import XCTest
@testable import Nodee

final class FileSystemServiceTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("NodeeTests-FSS-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root, FileManager.default.fileExists(atPath: root.path) {
            try FileManager.default.removeItem(at: root)
        }
        root = nil
    }

    @discardableResult
    private func makeFile(_ name: String, in dir: URL? = nil, contents: String = "x") throws -> URL {
        let url = (dir ?? root).appendingPathComponent(name)
        try contents.data(using: .utf8)!.write(to: url)
        return url
    }

    @discardableResult
    private func makeDir(_ name: String, in dir: URL? = nil) throws -> URL {
        let url = (dir ?? root).appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - exists

    func testExists() throws {
        let file = try makeFile("here.txt")
        XCTAssertTrue(FileSystemService.exists(file))
        XCTAssertFalse(FileSystemService.exists(root.appendingPathComponent("nope.txt")))
    }

    // MARK: - children(of:)

    func testChildrenSkipsHiddenFiles() throws {
        try makeFile("visible.txt")
        try makeFile(".hidden")
        let kids = FileSystemService.children(of: root)
        XCTAssertEqual(kids.map(\.name), ["visible.txt"])
    }

    func testChildrenFoldersFirstThenCaseInsensitiveName() throws {
        try makeFile("banana.txt")
        try makeFile("Apple.txt")
        try makeDir("Zebra")
        try makeDir("alpha")
        let kids = FileSystemService.children(of: root)
        // Folders first (alpha, Zebra — case-insensitive), then files (Apple, banana).
        XCTAssertEqual(kids.map(\.name), ["alpha", "Zebra", "Apple.txt", "banana.txt"])
    }

    func testChildrenOfInaccessibleReturnsEmpty() {
        let missing = root.appendingPathComponent("does-not-exist", isDirectory: true)
        XCTAssertEqual(FileSystemService.children(of: missing), [])
    }

    // MARK: - Collision resolution via duplicate / copy

    func testDuplicateAppendsTwoBeforeExtension() throws {
        let file = try makeFile("report.txt")
        let dup = try XCTUnwrap(FileSystemService.duplicate(file))
        XCTAssertEqual(dup.lastPathComponent, "report 2.txt")
        XCTAssertTrue(FileSystemService.exists(dup))
    }

    func testDuplicateIncrementsPastExistingCopies() throws {
        let file = try makeFile("report.txt")
        try makeFile("report 2.txt")
        try makeFile("report 3.txt")
        let dup = try XCTUnwrap(FileSystemService.duplicate(file))
        XCTAssertEqual(dup.lastPathComponent, "report 4.txt")
    }

    func testDuplicateWithoutExtension() throws {
        let file = try makeFile("README")
        let dup = try XCTUnwrap(FileSystemService.duplicate(file))
        XCTAssertEqual(dup.lastPathComponent, "README 2")
    }

    func testCopyIntoFolderResolvesCollision() throws {
        let source = try makeFile("data.json", contents: "{}")
        let dest = try makeDir("dest")
        // First copy lands at the exact name.
        let first = FileSystemService.copy([source], into: dest)
        XCTAssertEqual(first.map(\.lastPathComponent), ["data.json"])
        // Second copy of the same source collides → "data 2.json".
        let second = FileSystemService.copy([source], into: dest)
        XCTAssertEqual(second.map(\.lastPathComponent), ["data 2.json"])
        XCTAssertEqual(Set(FileSystemService.children(of: dest).map(\.name)), ["data.json", "data 2.json"])
    }

    func testCopyIntoOwnFolderClonesWithSuffix() throws {
        // Copying a file into its own parent resolves the collision to "self 2.txt"
        // (the no-op guard only fires when the resolved name equals the source).
        let source = try makeFile("self.txt")
        let result = FileSystemService.copy([source], into: root)
        XCTAssertEqual(result.map(\.lastPathComponent), ["self 2.txt"])
    }

    // MARK: - move into folder

    func testMoveIntoFolderResolvesCollision() throws {
        let dest = try makeDir("dest")
        try makeFile("clash.txt", in: dest)            // occupant already there
        let source = try makeFile("clash.txt")          // same name at root
        let moved = try XCTUnwrap(FileSystemService.move(source, into: dest))
        XCTAssertEqual(moved.lastPathComponent, "clash 2.txt")
        XCTAssertFalse(FileSystemService.exists(source))
    }

    func testMoveIntoCurrentParentBecomesNoOpOnlyWhenNameIsFree() throws {
        // move(into:) resolves a non-colliding name *first*, so dropping a file into
        // its own parent (where its name already exists) yields "stay 2.txt" — the
        // self-move guard (destination == source) only short-circuits when the
        // resolved name happens to equal the source (i.e. the slot is free).
        let source = try makeFile("stay.txt")
        let result = try XCTUnwrap(FileSystemService.move(source, into: root))
        XCTAssertEqual(result.lastPathComponent, "stay 2.txt")
        XCTAssertFalse(FileSystemService.exists(source)) // moved to the new name
    }

    // MARK: - createFolder / createFile

    func testCreateFolderResolvesCollision() throws {
        let first = try XCTUnwrap(FileSystemService.createFolder(in: root, name: "New"))
        XCTAssertEqual(first.lastPathComponent, "New")
        let second = try XCTUnwrap(FileSystemService.createFolder(in: root, name: "New"))
        XCTAssertEqual(second.lastPathComponent, "New 2")
    }

    func testCreateFileResolvesCollision() throws {
        let first = try XCTUnwrap(FileSystemService.createFile(in: root, name: "note.txt"))
        XCTAssertEqual(first.lastPathComponent, "note.txt")
        let second = try XCTUnwrap(FileSystemService.createFile(in: root, name: "note.txt"))
        XCTAssertEqual(second.lastPathComponent, "note 2.txt")
    }

    // MARK: - rename

    func testRenameResolvesCollision() throws {
        try makeFile("taken.txt")
        let file = try makeFile("orig.txt")
        let renamed = try XCTUnwrap(FileSystemService.rename(file, to: "taken.txt"))
        XCTAssertEqual(renamed.lastPathComponent, "taken 2.txt")
    }

    func testRenameToSameNameIsNil() throws {
        let file = try makeFile("same.txt")
        XCTAssertNil(FileSystemService.rename(file, to: "same.txt"))
    }

    func testRenameEmptyIsNil() throws {
        let file = try makeFile("x.txt")
        XCTAssertNil(FileSystemService.rename(file, to: "   "))
    }

    // MARK: - relativePath

    func testRelativePathNested() {
        let r = URL(fileURLWithPath: "/Users/me/proj")
        let u = URL(fileURLWithPath: "/Users/me/proj/src/main.swift")
        XCTAssertEqual(FileSystemService.relativePath(of: u, root: r), "src/main.swift")
    }

    func testRelativePathOutsideRootFallsBackToLastComponent() {
        let r = URL(fileURLWithPath: "/Users/me/proj")
        let u = URL(fileURLWithPath: "/etc/hosts")
        XCTAssertEqual(FileSystemService.relativePath(of: u, root: r), "hosts")
    }
}
