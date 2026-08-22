//
//  QRCodeImageDecoder.swift
//  cookbook
//
//  Decodes a QR code from a static image (e.g. one picked from a file, as
//  opposed to a live camera frame) — CoreImage's CIDetector, not Vision's
//  VNDetectBarcodesRequest or VisionKit's DataScannerViewController.
//  VNDetectBarcodesRequest needs to stand up a CoreML inference context,
//  which reliably throws "Could not create inference context" (Vision
//  error 9) in the iOS Simulator regardless of image quality — untestable
//  there, and no more reliable on a real device for this exact "read one
//  QR from a standalone image" case than the older, purpose-built
//  CIDetector algorithm, which has no ML/inference dependency at all and
//  works identically in the Simulator and on a real device.
//

import CoreGraphics
import CoreImage
import Foundation
import ImageIO

enum QRCodeImageDecoder {
    /// Nil if the image has no QR code, or isn't decodable image data at
    /// all — both are just "no code found," not surfaced differently.
    static func decode(from data: Data) -> String? {
        guard let ciImage = CIImage(data: data) else { return nil }
        return decode(from: ciImage)
    }

    static func decode(from cgImage: CGImage) -> String? {
        decode(from: CIImage(cgImage: cgImage))
    }

    private static func decode(from ciImage: CIImage) -> String? {
        let detector = CIDetector(
            ofType: CIDetectorTypeQRCode,
            context: nil,
            options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]
        )
        let features = detector?.features(in: ciImage) as? [CIQRCodeFeature] ?? []
        return features.first?.messageString
    }
}
