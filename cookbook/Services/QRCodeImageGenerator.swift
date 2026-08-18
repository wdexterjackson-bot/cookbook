//
//  QRCodeImageGenerator.swift
//  cookbook
//
//  CoreImage's built-in CIFilter, not a third-party library.
//

import CoreImage.CIFilterBuiltins
import SwiftUI

enum QRCodeImageGenerator {
    /// Nil only on a genuine CoreImage failure (encoding an implausibly
    /// long string, etc.) — never for ordinary group/friend IDs.
    static func image(for string: String) -> Image? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let outputImage = filter.outputImage else { return nil }

        // The raw CIImage is only a few points per module — scaling here
        // keeps this independent of whatever size the caller displays it
        // at, without blurring from an implicit resize.
        let scaled = outputImage.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }

        #if canImport(UIKit)
        return Image(uiImage: UIImage(cgImage: cgImage))
        #elseif canImport(AppKit)
        return Image(nsImage: NSImage(cgImage: cgImage, size: .zero))
        #else
        return Image(decorative: cgImage, scale: 1.0)
        #endif
    }
}
