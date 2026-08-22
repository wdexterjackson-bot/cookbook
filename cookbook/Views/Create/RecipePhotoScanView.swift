//
//  RecipePhotoScanView.swift
//  cookbook
//
//  CreateHubView's "Photo / Scan" entry point. iOS/iPadOS only — camera
//  capture (UIImagePickerController; there's still no public SwiftUI-
//  native camera API) and Vision's on-device text recognition are both
//  UIKit/Vision, unavailable on tvOS and not meaningful on macOS (no
//  camera). Recognized text feeds straight into the same on-device AI
//  import (CreateEditRecipeView.performImport) the Paste Recipe button
//  already uses — this view's whole job is turning a photo into that
//  same plain text, nothing more.
//

#if os(iOS)
import SwiftUI
import SwiftData
import PhotosUI
import Vision
import UIKit

struct RecipePhotoScanView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isPresentingCamera = false
    @State private var isRecognizing = false
    @State private var errorMessage: String?
    /// Non-nil the moment text recognition succeeds — drives the
    /// full-screen hand-off into CreateEditRecipeView. Set back to nil
    /// (and this whole screen dismissed with it) once that editor closes,
    /// so returning here would show a fresh, unused scan screen rather
    /// than a stale result.
    @State private var recognizedText: String?

    private var isCameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()
                Image(systemName: "text.viewfinder")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.accentColor)
                Text("Take a photo of a recipe card, cookbook page, or printed recipe — on-device text recognition pulls out the words, then the same Import used by Paste Recipe sorts them into Ingredients and Steps for you to review.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                VStack(spacing: 12) {
                    if isCameraAvailable {
                        Button {
                            isPresentingCamera = true
                        } label: {
                            Label("Take Photo", systemImage: "camera")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        Label("Choose Photo", systemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, 40)

                if isRecognizing {
                    ProgressView("Reading text…")
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                Spacer()
            }
            .navigationTitle("Photo / Scan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .fullScreenCover(isPresented: $isPresentingCamera) {
                CameraCaptureView { image in
                    isPresentingCamera = false
                    if let image {
                        recognizeText(in: image)
                    }
                }
                .ignoresSafeArea()
            }
            .onChange(of: selectedPhotoItem) { _, newItem in
                Task {
                    guard let data = try? await newItem?.loadTransferable(type: Data.self),
                          let uiImage = UIImage(data: data) else { return }
                    recognizeText(in: uiImage)
                }
            }
            .fullScreenCover(isPresented: Binding(
                get: { recognizedText != nil },
                set: { isPresented in
                    if !isPresented {
                        recognizedText = nil
                        dismiss()
                    }
                }
            )) {
                if let recognizedText {
                    CreateEditRecipeView(mode: .create, initialScannedText: recognizedText)
                }
            }
        }
    }

    private func recognizeText(in image: UIImage) {
        guard let cgImage = image.cgImage else {
            errorMessage = "Couldn't read that image."
            return
        }
        isRecognizing = true
        errorMessage = nil
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        let request = VNRecognizeTextRequest { request, error in
            DispatchQueue.main.async {
                isRecognizing = false
                if let error {
                    errorMessage = error.localizedDescription
                    return
                }
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                guard !lines.isEmpty else {
                    errorMessage = "Couldn't find any text in that photo — try a clearer, well-lit shot."
                    return
                }
                recognizedText = lines.joined(separator: "\n")
            }
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
            } catch {
                DispatchQueue.main.async {
                    isRecognizing = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

private extension CGImagePropertyOrientation {
    /// Vision needs a CGImagePropertyOrientation, not UIImage's own
    /// Orientation — this is Apple's documented mapping between the two
    /// (same raw ordering both enums already use).
    init(_ uiOrientation: UIImage.Orientation) {
        switch uiOrientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}

/// Thin UIImagePickerController wrapper — camera capture still has no
/// public SwiftUI-native API; this is still Apple's own recommended
/// approach for a simple one-shot photo.
private struct CameraCaptureView: UIViewControllerRepresentable {
    let onCapture: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (UIImage?) -> Void

        init(onCapture: @escaping (UIImage?) -> Void) {
            self.onCapture = onCapture
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onCapture(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCapture(nil)
        }
    }
}

#Preview {
    RecipePhotoScanView()
        .modelContainer(for: Recipe.self, inMemory: true)
        .environment(AccountState(authService: FakeAuthService()))
        .environment(ActiveCookbookState())
}
#endif
