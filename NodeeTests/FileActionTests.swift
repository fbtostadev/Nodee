//
//  FileActionTests.swift
//  NodeeTests
//
//  Unit tests for FileAction.reverted() — the inverse-action logic behind the
//  undo/redo stacks. These exercise real disk mutations in a temporary directory
//  so the round-trips (move ⇄ move, create → trash) reflect actual FileManager
//  behavior, not a stub.
//

import XCTest
@testable import Nodee

final class FileActionTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("NodeeTests-FileAction-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root, FileManager.default.fileExists(atPath: root.path) {
            try FileManager.default.removeItem(at: root)
        }
        root = nil
    }

    // MARK: - Helpers

    @discardableResult
    private func makeFile(_ name: String, contents: String = "x") throws -> URL {
        let url = root.appendingPathComponent(name)
        try contents.data(using: .utf8)!.write(to: url)
        return url
    }

    @discardableResult
    private func makeDir(_ name: String) throws -> URL {
        let url = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    // MARK: - move

    func testMoveRevertedReturnsInverseMove() throws {
        let folderA = try makeDir("A")
        let folderB = try makeDir("B")
        let file = try makeFile("doc.txt")
        // Simulate a completed move A/.. -> B/doc.txt
        let moved = FileSystemService.move(file, into: folderB)
        let dest = try XCTUnwrap(moved)
        XCTAssertTrue(exists(dest))
        XCTAssertFalse(exists(file))

        let action = FileAction.move(items: [(from: file, to: dest)])
        let inverse = try XCTUnwrap(action.reverted())

        // The file is back at its original location...
        XCTAssertTrue(exists(file))
        XCTAssertFalse(exists(dest))
        // ...and the inverse action is a move that would replay the original (to -> from).
        guard case .move(let items) = inverse else {
            return XCTFail("expected .move, got \(inverse)")
        }
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].from.standardizedFileURL, dest.standardizedFileURL)
        XCTAssertEqual(items[0].to.standardizedFileURL, file.standardizedFileURL)
        _ = folderA
    }

    func testMoveRoundTripReplaysOriginal() throws {
        let folderB = try makeDir("B")
        let file = try makeFile("doc.txt")
        let dest = try XCTUnwrap(FileSystemService.move(file, into: folderB))

        let original = FileAction.move(items: [(from: file, to: dest)])
        let inverse = try XCTUnwrap(original.reverted())  // file now back at original
        let replay = try XCTUnwrap(inverse.reverted())    // file back in folderB

        XCTAssertTrue(exists(dest))
        XCTAssertFalse(exists(file))
        guard case .move(let items) = replay else { return XCTFail("expected .move") }
        XCTAssertEqual(items[0].to.standardizedFileURL, dest.standardizedFileURL)
    }

    func testMoveRevertedReturnsNilWhenTargetGone() throws {
        let missingFrom = root.appendingPathComponent("gone-src.txt")
        let missingTo = root.appendingPathComponent("gone-dst.txt")
        // Neither end exists on disk → nothing can be reverted.
        let action = FileAction.move(items: [(from: missingFrom, to: missingTo)])
        XCTAssertNil(action.reverted())
    }

    // MARK: - trash

    func testTrashRevertedRestoresAndReturnsMove() throws {
        let file = try makeFile("trashme.txt", contents: "hello")
        let pairs = FileSystemService.moveToTrash([file])
        let pair = try XCTUnwrap(pairs.first)
        XCTAssertFalse(exists(file))
        XCTAssertTrue(exists(pair.trashed))

        let action = FileAction.trash(items: [(original: pair.original, trashed: pair.trashed)])
        let inverse = try XCTUnwrap(action.reverted())

        // Restored to the original spot...
        XCTAssertTrue(exists(file))
        XCTAssertFalse(exists(pair.trashed))
        // ...and replaying the inverse move sends it back to the Trash path.
        guard case .move(let items) = inverse else { return XCTFail("expected .move") }
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].from.standardizedFileURL, pair.trashed.standardizedFileURL)
        XCTAssertEqual(items[0].to.standardizedFileURL, pair.original.standardizedFileURL)
    }

    func testTrashRevertedReturnsNilWhenTrashedItemGone() throws {
        let original = root.appendingPathComponent("orig.txt")
        let trashed = root.appendingPathComponent("phantom-in-trash.txt")
        let action = FileAction.trash(items: [(original: original, trashed: trashed)])
        XCTAssertNil(action.reverted())
    }

    // MARK: - create

    func testCreateRevertedTrashesAndReturnsTrash() throws {
        let created = try makeFile("fresh.txt")
        XCTAssertTrue(exists(created))

        let action = FileAction.create(urls: [created])
        let inverse = try XCTUnwrap(action.reverted())

        // The created item is gone from disk (in the Trash)...
        XCTAssertFalse(exists(created))
        // ...and the inverse is a .trash that restore (redo) can put back.
        guard case .trash(let items) = inverse else { return XCTFail("expected .trash") }
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].original.standardizedFileURL, created.standardizedFileURL)
    }

    func testCreateRevertedReturnsNilWhenNothingExists() throws {
        let phantom = root.appendingPathComponent("never-created.txt")
        let action = FileAction.create(urls: [phantom])
        XCTAssertNil(action.reverted())
    }

    func testResultingURLsMatchEachCase() throws {
        let a = root.appendingPathComponent("a")
        let b = root.appendingPathComponent("b")
        XCTAssertEqual(FileAction.move(items: [(from: a, to: b)]).resultingURLs, [b])
        XCTAssertEqual(FileAction.trash(items: [(original: a, trashed: b)]).resultingURLs, [b])
        XCTAssertEqual(FileAction.create(urls: [a, b]).resultingURLs, [a, b])
    }
}
