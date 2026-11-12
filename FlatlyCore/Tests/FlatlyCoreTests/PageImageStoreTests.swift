import Testing
import Foundation
@testable import FlatlyCore

struct PageImageStoreTests {
    private func makeTempRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("PageImageStoreTests-\(UUID().uuidString)", isDirectory: true)
    }

    @Test func roundTrip() throws {
        let root = makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PageImageStore(rootDirectory: root)
        let a = UUID(), b = UUID()

        #expect(try store.allPageIDs().isEmpty)
        #expect(!store.exists(for: a, kind: .original))

        try store.write(Data([1, 2, 3]), for: a, kind: .original)
        try store.write(Data([4, 5]), for: a, kind: .thumb)
        try store.write(Data([6]), for: b, kind: .processed)

        #expect(store.exists(for: a, kind: .original))
        #expect(store.exists(for: a, kind: .thumb))
        #expect(!store.exists(for: a, kind: .source))
        #expect(try store.read(for: a, kind: .original) == Data([1, 2, 3]))
        #expect(try store.read(for: b, kind: .processed) == Data([6]))
        #expect(store.url(for: a, kind: .original).path.hasSuffix("\(a.uuidString)/original.jpg"))
        #expect(Set(try store.allPageIDs()) == [a, b])

        // Overwrite is atomic and replaces content.
        try store.write(Data([9, 9]), for: a, kind: .original)
        #expect(try store.read(for: a, kind: .original) == Data([9, 9]))

        try store.delete(pageID: a)
        #expect(!store.exists(for: a, kind: .original))
        #expect(!store.exists(for: a, kind: .thumb))
        #expect(try store.allPageIDs() == [b])

        // Deleting something that does not exist is not an error.
        try store.delete(pageID: a)
        try store.delete(pageID: UUID())
    }

    @Test func readOfMissingFileThrowsIO() throws {
        let root = makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PageImageStore(rootDirectory: root)
        do {
            _ = try store.read(for: UUID(), kind: .processed)
            Issue.record("expected an error")
        } catch let error as FlatlyCoreError {
            guard case .io = error else {
                Issue.record("expected .io, got \(error)")
                return
            }
        }
    }

    @Test func allPageIDsIgnoresNonUUIDEntries() throws {
        let root = makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PageImageStore(rootDirectory: root)
        let id = UUID()
        try store.write(Data([1]), for: id, kind: .original)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("not-a-uuid"), withIntermediateDirectories: true)
        try Data([0]).write(to: root.appendingPathComponent(UUID().uuidString))   // a file, not a directory
        #expect(try store.allPageIDs() == [id])
    }

    @Test func defaultRootExists() throws {
        let root = try PageImageStore.defaultRoot()
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
        #expect(root.path.hasSuffix("Flatly/Pages"))
    }

    // MARK: Orphan sweep

    /// Backdates a page folder's modification date.
    private func age(_ store: PageImageStore, _ id: UUID, by seconds: TimeInterval) throws {
        let dir = store.url(for: id, kind: .original).deletingLastPathComponent()
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -seconds)], ofItemAtPath: dir.path)
    }

    @Test func removeOrphanedPagesKeepsKnownAndYoungFolders() throws {
        let root = makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PageImageStore(rootDirectory: root)
        let known = UUID(), orphan = UUID(), young = UUID()
        for id in [known, orphan, young] { try store.write(Data([1]), for: id, kind: .original) }
        try age(store, known, by: 3600)
        try age(store, orphan, by: 3600)

        let removed = try store.removeOrphanedPages(keeping: [known], modifiedBefore: Date(timeIntervalSinceNow: -600))
        #expect(removed == [orphan])
        #expect(Set(try store.allPageIDs()) == [known, young])
    }

    @Test func removeOrphanedPagesDeletesNothingWhenNoPagesAreKnown() throws {
        let root = makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PageImageStore(rootDirectory: root)
        let a = UUID(), b = UUID()
        for id in [a, b] {
            try store.write(Data([1]), for: id, kind: .original)
            try age(store, id, by: 3600)
        }

        let removed = try store.removeOrphanedPages(keeping: [], modifiedBefore: Date(timeIntervalSinceNow: -600))
        #expect(removed.isEmpty)
        #expect(Set(try store.allPageIDs()) == [a, b])
    }

    @Test func removeOrphanedPagesWithMissingRootIsNoOp() throws {
        let store = PageImageStore(rootDirectory: makeTempRoot())
        let removed = try store.removeOrphanedPages(keeping: [UUID()], modifiedBefore: Date())
        #expect(removed.isEmpty)
    }

    // MARK: Trash

    private func trashEntries(_ root: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent(".trash").path)
    }

    @Test func moveToTrashHidesPageAndEmptyTrashErasesIt() throws {
        let root = makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PageImageStore(rootDirectory: root)
        let a = UUID(), b = UUID()
        try store.write(Data([1]), for: a, kind: .original)
        try store.write(Data([2]), for: a, kind: .thumb)
        try store.write(Data([3]), for: b, kind: .original)

        try store.moveToTrash(pageID: a)
        #expect(!store.exists(for: a, kind: .original))
        #expect(!store.exists(for: a, kind: .thumb))
        #expect(try store.allPageIDs() == [b])
        #expect(try trashEntries(root) == [a.uuidString])

        #expect(store.emptyTrash() == 1)
        // The trash folder itself stays (a concurrent move may be about to use it).
        #expect(try trashEntries(root).isEmpty)
        #expect(try store.read(for: b, kind: .original) == Data([3]))
        #expect(try store.allPageIDs() == [b])
    }

    @Test func moveToTrashOfMissingPageIsNoOp() throws {
        let root = makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PageImageStore(rootDirectory: root)
        try store.moveToTrash(pageID: UUID())
        #expect(store.emptyTrash() == 0)
    }

    @Test func emptyTrashWithMissingRootIsNoOp() {
        let store = PageImageStore(rootDirectory: makeTempRoot())
        #expect(store.emptyTrash() == 0)
    }

    @Test func trashedFoldersAreIgnoredByOrphanSweep() throws {
        let root = makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PageImageStore(rootDirectory: root)
        let a = UUID(), b = UUID(), c = UUID()
        for id in [a, b, c] {
            try store.write(Data([1]), for: id, kind: .original)
            try age(store, id, by: 3600)
        }
        try store.moveToTrash(pageID: a)

        let removed = try store.removeOrphanedPages(keeping: [b], modifiedBefore: Date(timeIntervalSinceNow: -600))
        #expect(removed == [c])
        #expect(try trashEntries(root) == [a.uuidString])

        // An empty library still sweeps nothing, but the trash is erased regardless.
        #expect(try store.removeOrphanedPages(keeping: [], modifiedBefore: Date()).isEmpty)
        #expect(try store.allPageIDs() == [b])
        #expect(store.emptyTrash() == 1)
        #expect(try trashEntries(root).isEmpty)
    }

    @Test func editWriteDoesNotRecreateTrashedPageFolder() throws {
        let root = makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PageImageStore(rootDirectory: root)
        let a = UUID()
        try store.write(Data([1]), for: a, kind: .original)
        try store.moveToTrash(pageID: a)

        do {
            try store.write(Data([2]), for: a, kind: .processed, createsPageFolder: false)
            Issue.record("expected an error")
        } catch let error as FlatlyCoreError {
            guard case .io = error else {
                Issue.record("expected .io, got \(error)")
                return
            }
        }
        #expect(try !store.allPageIDs().contains(a))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(a.uuidString).path))
        #expect(!store.exists(for: a, kind: .processed))
    }

    @Test func editWriteReplacesFileInExistingFolder() throws {
        let root = makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PageImageStore(rootDirectory: root)
        let a = UUID()
        try store.write(Data([1]), for: a, kind: .original)
        try store.write(Data([2]), for: a, kind: .processed, createsPageFolder: false)
        try store.write(Data([3, 4]), for: a, kind: .processed, createsPageFolder: false)
        #expect(try store.read(for: a, kind: .processed) == Data([3, 4]))
        #expect(try store.read(for: a, kind: .original) == Data([1]))
    }

    @Test func moveToTrashReplacesStaleTrashEntry() throws {
        let root = makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PageImageStore(rootDirectory: root)
        let a = UUID()
        let stale = root.appendingPathComponent(".trash").appendingPathComponent(a.uuidString)
        try FileManager.default.createDirectory(at: stale, withIntermediateDirectories: true)
        try Data([0]).write(to: stale.appendingPathComponent("old.jpg"))
        try store.write(Data([1]), for: a, kind: .original)

        try store.moveToTrash(pageID: a)
        #expect(!store.exists(for: a, kind: .original))
        #expect(FileManager.default.fileExists(atPath: stale.appendingPathComponent("original.jpg").path))
        #expect(!FileManager.default.fileExists(atPath: stale.appendingPathComponent("old.jpg").path))
        #expect(store.emptyTrash() == 1)
    }
}
