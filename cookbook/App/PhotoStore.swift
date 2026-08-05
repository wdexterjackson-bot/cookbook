//
//  PhotoStore.swift
//  cookbook
//
//  Recipe photos are stored as files in the app's local container and
//  referenced from Recipe by filename, not as raw Data blobs in SwiftData,
//  so large galleries don't bloat the store file.
//

import Foundation

enum PhotoStore {
    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = base.appendingPathComponent("RecipePhotos", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func save(_ data: Data) throws -> String {
        let filename = "\(UUID().uuidString).jpg"
        try data.write(to: url(for: filename))
        return filename
    }

    static func url(for filename: String) -> URL {
        directory.appendingPathComponent(filename)
    }

    static func data(for filename: String) -> Data? {
        try? Data(contentsOf: url(for: filename))
    }

    static func delete(_ filename: String) {
        try? FileManager.default.removeItem(at: url(for: filename))
    }
}
