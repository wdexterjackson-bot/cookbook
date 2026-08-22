//
//  QRCodeImageGenerator.swift
//  cookbook
//
//  CoreImage's built-in CIFilter, not a third-party library.
//

import CoreImage.CIFilterBuiltins
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

enum QRCodeImageGenerator {
    /// Encodes the generated code as lossless PNG bytes — what
    /// QRCodeDisplayView's ShareLink actually hands off, rather than
    /// SwiftUI's own `Image: Transferable` conformance. That conformance
    /// re-renders the Image through its own (opaque, environment-
    /// dependent) pipeline to produce a transfer representation, which
    /// isn't guaranteed to preserve this image's exact pixels — a real
    /// risk for something that needs to stay scannable, unlike an
    /// ordinary photo where a little resampling is invisible. Building
    /// the PNG directly from the same CGImage this type generates removes
    /// that whole source of uncertainty.
    static func pngData(for string: String) -> Data? {
        guard let cgImage = cgImage(for: string) else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    /// Nil only on a genuine CoreImage failure (encoding an implausibly
    /// long string, etc.) — never for ordinary group/friend IDs.
    static func image(for string: String) -> Image? {
        guard let cgImage = cgImage(for: string) else { return nil }

        #if canImport(UIKit)
        return Image(uiImage: UIImage(cgImage: cgImage))
        #elseif canImport(AppKit)
        return Image(nsImage: NSImage(cgImage: cgImage, size: .zero))
        #else
        return Image(decorative: cgImage, scale: 1.0)
        #endif
    }

    /// Split out from `image(for:)` so tests can round-trip the raw
    /// CGImage through QRCodeImageDecoder — SwiftUI's Image type doesn't
    /// expose its own backing CGImage.
    static func cgImage(for string: String) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let outputImage = filter.outputImage else { return nil }

        // The raw CIImage is only a few points per module — scaling here
        // keeps this independent of whatever size the caller displays it
        // at, without blurring from an implicit resize.
        let scaleFactor: CGFloat = 10
        let scaled = outputImage.transformed(by: CGAffineTransform(scaleX: scaleFactor, y: scaleFactor))

        // A blank "quiet zone" margin around the modules is part of the QR
        // standard, not just cosmetic padding — CIQRCodeGenerator's raw
        // output has none at all (modules run flush to the image edge).
        // Live camera scanning (VisionKit's DataScannerViewController)
        // tolerates that fine, since whatever real-world backdrop
        // surrounds the screen/printout supplies a quiet zone on its own;
        // a saved, cropped-to-the-edge PNG has no such backdrop, and
        // QRCodeImageDecoder's static-image Vision request reliably fails
        // to detect a code with no quiet zone. 4 modules on each side,
        // the spec's own minimum.
        let quietZoneModules: CGFloat = 4
        let margin = quietZoneModules * scaleFactor
        let paddedExtent = scaled.extent.insetBy(dx: -margin, dy: -margin)
        let padded = scaled.composited(over: CIImage(color: .white).cropped(to: paddedExtent))

        let context = CIContext()
        return context.createCGImage(padded, from: paddedExtent)
    }
}
