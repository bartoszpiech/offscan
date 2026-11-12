import Foundation

/// On-disk image files per page: `<root>/<pageID>/<kind>.jpg`. Folders of deleted pages wait in
/// the hidden `<root>/.trash` until `emptyTrash()` erases them (`moveToTrash(pageID:)`).
public struct PageImageStore: Sendable {
    public enum Kind: String, Sendable, CaseIterable {
        /// Untouched imported photo (imports only).
        case source
        /// Perspective-corrected, unfiltered, unrotated page.
        case original
        /// Fully rendered page (crop + filter + rotation + signature).
        case processed
        /// Small preview of `processed`.
        case thumb
    }

    public let rootDirectory: URL

    public init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory
    }

    /// `Application Support/Flatly/Pages`, created if needed. Intentionally *not* excluded from
    /// backup: users expect their scans to be part of their device backups.
    public static func defaultRoot() throws -> URL {
        let fm = FileManager.default
        guard let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw FlatlyCoreError.io("Application Support directory unavailable")
        }
        let root = support
            .appendingPathComponent("Flatly", isDirectory: true)
            .appendingPathComponent("Pages", isDirectory: true)
        do {
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
        } catch {
            throw FlatlyCoreError.io("Cannot create \(root.path): \(error.localizedDescription)")
        }
        return root
    }

    public func url(for pageID: UUID, kind: Kind) -> URL {
        pageDirectory(for: pageID)
            .appendingPathComponent("\(kind.rawValue).jpg", isDirectory: false)
    }

    /// Atomic write. With `createsPageFolder` (the default) the page directory is created if
    /// needed; pass false for edits of an existing page: a page deleted (and trashed) while it was
    /// being rendered must never get its folder back, so the write then throws
    /// `FlatlyCoreError.io` instead.
    public func write(_ data: Data, for pageID: UUID, kind: Kind, createsPageFolder: Bool = true) throws {
        do {
            if createsPageFolder {
                try FileManager.default.createDirectory(at: pageDirectory(for: pageID), withIntermediateDirectories: true)
            }
            try data.write(to: url(for: pageID, kind: kind), options: .atomic)
        } catch {
            throw FlatlyCoreError.io("Cannot write \(kind.rawValue) for page \(pageID): \(error.localizedDescription)")
        }
    }

    /// Throws `FlatlyCoreError.io` when the file is missing or unreadable.
    public func read(for pageID: UUID, kind: Kind) throws -> Data {
        do {
            return try Data(contentsOf: url(for: pageID, kind: kind))
        } catch {
            throw FlatlyCoreError.io("Cannot read \(kind.rawValue) for page \(pageID): \(error.localizedDescription)")
        }
    }

    public func exists(for pageID: UUID, kind: Kind) -> Bool {
        FileManager.default.fileExists(atPath: url(for: pageID, kind: kind).path)
    }

    /// Removes every file for the page. Not an error if nothing exists.
    public func delete(pageID: UUID) throws {
        let dir = pageDirectory(for: pageID)
        let fm = FileManager.default
        guard fm.fileExists(atPath: dir.path) else { return }
        do {
            try fm.removeItem(at: dir)
        } catch {
            throw FlatlyCoreError.io("Cannot delete page \(pageID): \(error.localizedDescription)")
        }
    }

    /// Moves the page's folder into the trash, so its files are gone from `url(for:kind:)`,
    /// `allPageIDs()` and the orphan sweep immediately: a single rename, cheap enough for the main
    /// actor. Erase the trash later, off the main actor, with `emptyTrash()`. A stale trash entry
    /// with the same ID is replaced. Not an error if the page has no folder.
    ///
    /// Only call it once the page's deletion has been saved: everything in the trash is erased
    /// unconditionally, even when the library is empty or can't be read.
    public func moveToTrash(pageID: UUID) throws {
        let fm = FileManager.default
        let dir = pageDirectory(for: pageID)
        guard fm.fileExists(atPath: dir.path) else { return }
        do {
            if !fm.fileExists(atPath: trashDirectory.path) {
                try fm.createDirectory(at: trashDirectory, withIntermediateDirectories: true)
                // Deleted scans must never reach a backup.
                var trash = trashDirectory
                var values = URLResourceValues()
                values.isExcludedFromBackup = true
                try? trash.setResourceValues(values)
            }
            let destination = trashDirectory.appendingPathComponent(pageID.uuidString, isDirectory: true)
            if fm.fileExists(atPath: destination.path) { try? fm.removeItem(at: destination) }
            try fm.moveItem(at: dir, to: destination)
        } catch {
            throw FlatlyCoreError.io("Cannot trash page \(pageID): \(error.localizedDescription)")
        }
    }

    /// Erases everything in the trash and returns how many entries were removed. Entries that
    /// fail to delete stay for the next call; the trash folder itself is kept, so a concurrent
    /// `moveToTrash(pageID:)` never loses its destination. Best effort, never throws.
    ///
    /// Everything in the trash belongs to pages whose deletion was saved, so this is safe to call
    /// at any time, including when the library is empty or can't be read.
    @discardableResult
    public func emptyTrash() -> Int {
        let fm = FileManager.default
        guard fm.fileExists(atPath: trashDirectory.path),
              let entries = try? fm.contentsOfDirectory(at: trashDirectory, includingPropertiesForKeys: nil, options: [])
        else { return 0 }
        var removed = 0
        for entry in entries where (try? fm.removeItem(at: entry)) != nil {
            removed += 1
        }
        return removed
    }

    /// IDs of every page directory under the root (subdirectories whose names parse as UUIDs).
    /// Returns an empty array when the root does not exist yet. The hidden trash is never listed.
    public func allPageIDs() throws -> [UUID] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: rootDirectory.path) else { return [] }
        let entries: [URL]
        do {
            entries = try fm.contentsOfDirectory(
                at: rootDirectory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            throw FlatlyCoreError.io("Cannot list \(rootDirectory.path): \(error.localizedDescription)")
        }
        return entries.compactMap { entry -> UUID? in
            let isDirectory = (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard isDirectory else { return nil }
            return UUID(uuidString: entry.lastPathComponent)
        }
        .sorted { $0.uuidString < $1.uuidString }
    }

    /// Deletes image folders that no page refers to: every page folder whose ID is not in
    /// `knownPageIDs` and whose folder was last modified before `cutoff`. Younger folders may
    /// belong to a capture that is still being saved. Folders whose date can't be read are kept.
    /// The trash is not swept here (see `emptyTrash()`).
    ///
    /// Safety valve: when `knownPageIDs` is empty, nothing is deleted. An empty library next to
    /// image folders more likely means the database wasn't read than that every scan is an orphan.
    /// Folders that fail to delete are skipped. Throws `FlatlyCoreError.io` only if the root can't
    /// be listed.
    /// - Returns: the IDs whose folders were removed.
    @discardableResult
    public func removeOrphanedPages(keeping knownPageIDs: Set<UUID>, modifiedBefore cutoff: Date) throws -> [UUID] {
        guard !knownPageIDs.isEmpty else { return [] }
        var removed: [UUID] = []
        for id in try allPageIDs() where !knownPageIDs.contains(id) {
            let dir = pageDirectory(for: id)
            guard let modified = try? dir.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                  modified < cutoff else { continue }
            if (try? delete(pageID: id)) != nil { removed.append(id) }
        }
        return removed
    }

    private func pageDirectory(for pageID: UUID) -> URL {
        rootDirectory.appendingPathComponent(pageID.uuidString, isDirectory: true)
    }

    /// Hidden and not a UUID, so `allPageIDs()` and the orphan sweep never see it.
    private var trashDirectory: URL {
        rootDirectory.appendingPathComponent(".trash", isDirectory: true)
    }
}
