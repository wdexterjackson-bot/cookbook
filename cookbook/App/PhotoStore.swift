//
//  PhotoStore.swift
//  cookbook
//
//  Recipe photos are stored as files in the app's local container and
//  referenced from Recipe by filename, not as raw Data blobs in SwiftData,
//  so large galleries don't bloat the store file.
//
//  Every photo — cover, hero, gallery, whether picked locally or pulled
//  down from a sync/restore — passes through save(_:), so downscaling
//  happens exactly once, here, rather than duplicated (or missed) at each
//  PhotosPicker call site. This matters well beyond local disk space:
//  Personal Cookbook Cloud Sync uploads whatever's on disk as-is, and an
//  unresized PhotosPicker selection can be several MB — at real user
//  counts that's real, ongoing Firebase Storage cost, not just a local
//  nicety.

import Foundation
#if os(iOS)
import UIKit
#endif

enum PhotoStore {
    /// Longest edge, in pixels, anything saved is downscaled to — well
    /// above what any screen in this app displays a photo at, but small
    /// enough to cut a typical several-MB PhotosPicker selection by
    /// 10-20x. Chosen once, here, rather than per-call-site so cover,
    /// hero, and gallery photos all get the exact same treatment.
    private static let maxDimension: CGFloat = 1600
    private static let jpegCompressionQuality: CGFloat = 0.7

    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = base.appendingPathComponent("RecipePhotos", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func save(_ data: Data) throws -> String {
        let filename = "\(UUID().uuidString).jpg"
        try downscaledJPEG(data).write(to: url(for: filename))
        return filename
    }

    /// Falls back to the original data untouched if it isn't decodable as
    /// an image (shouldn't happen for anything this app actually saves,
    /// but a lossless passthrough is safer than throwing away a photo
    /// over a decode hiccup) or already fits within maxDimension.
    private static func downscaledJPEG(_ data: Data) -> Data {
        #if os(iOS)
        guard let image = UIImage(data: data) else { return data }
        let longestEdge = max(image.size.width, image.size.height)
        guard longestEdge > maxDimension else {
            return image.jpegData(compressionQuality: jpegCompressionQuality) ?? data
        }
        let scale = maxDimension / longestEdge
        let targetSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return resized.jpegData(compressionQuality: jpegCompressionQuality) ?? data
        #else
        return data
        #endif
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
