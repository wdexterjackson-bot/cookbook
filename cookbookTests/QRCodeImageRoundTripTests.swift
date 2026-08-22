//
//  QRCodeImageRoundTripTests.swift
//  cookbookTests
//
//  Regression test for a real bug: QR codes generated and shared/saved by
//  this app could fail to decode when re-imported via "Choose a QR Code
//  Image." Root causes fixed: (1) QRCodeImageGenerator's output had no
//  quiet zone (blank margin) around the modules, which the QR standard
//  requires for reliable detection from a standalone image; (2)
//  QRCodeImageDecoder used Vision's VNDetectBarcodesRequest, which needs
//  a CoreML inference context that Vision error 9 ("Could not create
//  inference context") reliably fails to create in the iOS Simulator —
//  switched to CoreImage's CIDetector, which has no such dependency and
//  runs identically in the Simulator and on a real device.
//

import CoreGraphics
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import cookbook

struct QRCodeImageRoundTripTests {

    @Test func aGeneratedQRCodeDecodesBackToTheSameString() throws {
        let payload = "cookbook://friend/abc123-test-user-id"
        let cgImage = try #require(QRCodeImageGenerator.cgImage(for: payload))

        let decoded = QRCodeImageDecoder.decode(from: cgImage)

        #expect(decoded == payload)
    }

    /// The exact path a saved/shared image takes — round-tripped through
    /// PNG encoding, not just the in-memory CGImage.
    @Test func aGeneratedQRCodeSurvivesBeingSavedAsAStandalonePNG() throws {
        let payload = "cookbook://friend/xyz789-another-user"
        let pngData = try #require(QRCodeImageGenerator.pngData(for: payload))

        let decoded = QRCodeImageDecoder.decode(from: pngData)

        #expect(decoded == payload)
    }

    @Test func decodingNonImageDataReturnsNilRatherThanCrashing() {
        let garbage = Data([0x00, 0x01, 0x02, 0x03])

        #expect(QRCodeImageDecoder.decode(from: garbage) == nil)
    }
}
