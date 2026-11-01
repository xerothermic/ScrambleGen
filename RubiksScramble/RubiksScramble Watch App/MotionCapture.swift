import Foundation
import os

/// Raw motion files, one per solve, in Application Support/Motion.
@MainActor
final class MotionStore {
    static let shared = MotionStore()

    let directory: URL

    private init() {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        directory = base.appendingPathComponent("Motion", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func url(for id: UUID) -> URL { directory.appendingPathComponent("\(id.uuidString).sgm") }

    func delete(_ id: UUID) { try? FileManager.default.removeItem(at: url(for: id)) }

    func deleteAll() {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for f in files { try? FileManager.default.removeItem(at: f) }
    }
}
