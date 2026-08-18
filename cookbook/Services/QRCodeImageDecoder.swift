//
//  QRCodeImageDecoder.swift
//  cookbook
//
//  Decodes a QR code from a static image (e.g. one picked from a file, as
//  opposed to a live camera frame) — Vision's barcode detection, not
//  VisionKit's DataScannerViewController, since this doesn't need a
//  camera and isn't iOS-only: ImageIO/Vision both work on macOS too.
//

import CoreGraphics
import Foundation
import ImageIO
import Vision

enum QRCodeImageDecoder {
    /// Nil if the image has no QR code, or isn't decodable image data at
    /// all — both are just "no code found," not surfaced differently.
    static func decode(from data: Data) -> String? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        return decode(from: cgImage)
    }

    static func decode(from cgImage: CGImage) -> String? {
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        guard (try? handler.perform([request])) != nil else { return nil }
        for result in request.results ?? [] {
            if let payload = result.payloadStringValue {
                return payload
            }
        }
        return nil
    }
}
