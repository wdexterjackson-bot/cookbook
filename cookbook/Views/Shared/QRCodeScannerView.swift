//
//  QRCodeScannerView.swift
//  cookbook
//
//  VisionKit's DataScannerViewController (iOS 16+) — modern built-in
//  camera scanning, no AVCaptureMetadataOutput boilerplate. iOS-only:
//  DataScannerViewController is UIKit, not available on macOS/tvOS.
//

#if os(iOS)
import SwiftUI
import Vision
import VisionKit

struct QRCodeScannerView: View {
    let onScan: (QRCodePayload) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                    DataScannerRepresentable { payload in
                        onScan(payload)
                        dismiss()
                    }
                    .ignoresSafeArea()
                } else {
                    ContentUnavailableView(
                        "Scanning Not Available",
                        systemImage: "camera",
                        description: Text("This device can't scan QR codes, or camera access hasn't been granted.")
                    )
                }
            }
            .navigationTitle("Scan QR Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

/// Bridges VisionKit's UIKit-only scanner into SwiftUI. Recognizes any QR
/// code, but only ever acts on one whose payload actually parses as a
/// `QRCodePayload` — an unrelated QR code (a URL, a Wi-Fi code, etc.) is
/// silently ignored rather than surfaced as an error, since scanning
/// something unrelated isn't really a failure of this screen.
private struct DataScannerRepresentable: UIViewControllerRepresentable {
    let onRecognize: (QRCodePayload) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        try? controller.startScanning()
        return controller
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onRecognize: onRecognize)
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onRecognize: (QRCodePayload) -> Void
        // Guards against firing more than once — DataScannerViewController
        // keeps reporting the same recognized item on subsequent frames
        // until scanning stops, and the SwiftUI dismiss() this triggers
        // isn't necessarily instantaneous.
        private var hasRecognized = false

        init(onRecognize: @escaping (QRCodePayload) -> Void) {
            self.onRecognize = onRecognize
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !hasRecognized else { return }
            for item in addedItems {
                guard case .barcode(let barcode) = item,
                      let stringValue = barcode.payloadStringValue,
                      let payload = QRCodePayload(stringValue: stringValue) else { continue }
                hasRecognized = true
                onRecognize(payload)
                return
            }
        }
    }
}
#endif
