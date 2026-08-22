//
//  QRCodeImageGeneratorTests.swift
//  cookbookTests
//
//  Regression test for a real bug: QRCodeImageGenerator's output had no
//  quiet zone (blank margin) around the modules, so a QR code saved from
//  this app as a standalone image file could fail to be read back by
//  QRCodeImageDecoder — only live camera scanning (which gets a quiet
//  zone for free from whatever real-world backdrop surrounds the screen)
//  reliably worked. This checks pixel data directly rather than doing a
//  full Vision decode round-trip: VNDetectBarcodesRequest cannot create
//  an inference context in the iOS Simulator ("Could not create
//  inference context", Vision error 9) regardless of image quality, so a
//  decode-based test can't produce a reliable pass/fail signal here.
//

import CoreGraphics
import Testing
@testable import cookbook

struct QRCodeImageGeneratorTests {

    private func cornerPixelsAreNearWhite(_ cgImage: CGImage) -> Bool {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return false }
        var pixels = [UInt8](repeating: 0, count: cgImage.width * cgImage.height * 4)
        guard let context = CGContext(
            data: &pixels, width: cgImage.width, height: cgImage.height, bitsPerComponent: 8,
            bytesPerRow: cgImage.width * 4, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return false }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))

        func isNearWhite(x: Int, y: Int) -> Bool {
            let offset = (y * cgImage.width + x) * 4
            return pixels[offset] > 240 && pixels[offset + 1] > 240 && pixels[offset + 2] > 240
        }

        let inset = 5
        let corners = [
            (inset, inset),
            (cgImage.width - 1 - inset, inset),
            (inset, cgImage.height - 1 - inset),
            (cgImage.width - 1 - inset, cgImage.height - 1 - inset),
        ]
        return corners.allSatisfy { isNearWhite(x: $0.0, y: $0.1) }
    }

    @Test func generatedImageHasABlankQuietZoneMarginAroundTheModules() throws {
        let cgImage = try #require(QRCodeImageGenerator.cgImage(for: "cookbook://friend/abc123-test-user-id"))

        #expect(cornerPixelsAreNearWhite(cgImage))
    }

    @Test func generatedImageIsSignificantlyLargerThanTheBareModulesWouldBe() throws {
        // "hi" is a short payload, so at correction level M the raw
        // (unpadded, unscaled) module grid is only ~21x21 — a generated
        // image narrower than ~250px at the 10x scale factor would mean
        // the quiet zone margin silently isn't being applied.
        let cgImage = try #require(QRCodeImageGenerator.cgImage(for: "hi"))

        #expect(cgImage.width > 250)
        #expect(cgImage.height > 250)
    }
}
