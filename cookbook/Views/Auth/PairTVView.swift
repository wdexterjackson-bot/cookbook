//
//  PairTVView.swift
//  cookbook
//
//  Phone side of Apple TV phone-pairing sign-in (see TVPairingSignInView
//  for the TV side). Same three input methods as AddFriendView's QR
//  flow — a live camera scan (iOS-only), picking an existing QR image
//  (works on macOS too), or typing the 6-character code by hand — all
//  three converge on the same confirmation step before actually calling
//  TVPairingServicing.confirmPairingCode.
//

import SwiftUI
import UniformTypeIdentifiers

struct PairTVView: View {
    let pairingService: TVPairingServicing

    @Environment(\.dismiss) private var dismiss
    @State private var codeInput = ""
    @State private var pendingCode: String?
    @State private var isConfirming = false
    @State private var errorMessage: String?
    @State private var statusMessage: String?
    #if os(iOS)
    @State private var isPresentingScanner = false
    #endif
    #if os(iOS) || os(macOS)
    @State private var isPresentingImagePicker = false
    #endif

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("6-Character Code", text: $codeInput)
                        #if os(iOS)
                        .textInputAutocapitalization(.characters)
                        .keyboardType(.asciiCapable)
                        #endif
                        .autocorrectionDisabled()
                    Button("Continue") {
                        pendingCode = codeInput.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    .disabled(codeInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } header: {
                    Text("Enter the Code Shown on Your TV")
                }

                #if os(iOS) || os(macOS)
                Section {
                    #if os(iOS)
                    Button {
                        isPresentingScanner = true
                    } label: {
                        Label("Scan the TV's QR Code", systemImage: "qrcode.viewfinder")
                    }
                    #endif
                    Button {
                        isPresentingImagePicker = true
                    } label: {
                        Label("Choose a QR Code Image", systemImage: "photo")
                    }
                }
                #endif

                if let statusMessage {
                    Text(statusMessage).foregroundStyle(.green)
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .navigationTitle("Sign In a TV")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            #if os(iOS)
            .sheet(isPresented: $isPresentingScanner) {
                QRCodeScannerView { payload in
                    handleScannedPayload(payload)
                }
            }
            #endif
            #if os(iOS) || os(macOS)
            .fileImporter(isPresented: $isPresentingImagePicker, allowedContentTypes: [.image]) { result in
                handleImageFileSelection(result)
            }
            #endif
            .confirmationDialog(
                "Sign in on this TV?",
                isPresented: Binding(get: { pendingCode != nil }, set: { if !$0 { pendingCode = nil } }),
                titleVisibility: .visible
            ) {
                Button("Sign In") {
                    if let pendingCode {
                        Task { await confirm(pendingCode) }
                    }
                    pendingCode = nil
                }
                Button("Cancel", role: .cancel) { pendingCode = nil }
            } message: {
                Text("Anyone with access to that TV will be able to use your account.")
            }
        }
    }

    private func handleScannedPayload(_ payload: QRCodePayload) {
        guard case .tvPair(let code) = payload else {
            errorMessage = "That QR code isn't a TV sign-in code."
            return
        }
        errorMessage = nil
        pendingCode = code
    }

    #if os(iOS) || os(macOS)
    private func handleImageFileSelection(_ result: Result<URL, Error>) {
        errorMessage = nil
        statusMessage = nil
        switch result {
        case .failure(let error):
            errorMessage = error.localizedDescription
        case .success(let url):
            let isSecurityScoped = url.startAccessingSecurityScopedResource()
            defer { if isSecurityScoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url), let stringValue = QRCodeImageDecoder.decode(from: data) else {
                errorMessage = "Couldn't find a QR code in that image."
                return
            }
            guard let payload = QRCodePayload(stringValue: stringValue) else {
                errorMessage = "That QR code isn't from this app."
                return
            }
            handleScannedPayload(payload)
        }
    }
    #endif

    private func confirm(_ code: String) async {
        isConfirming = true
        errorMessage = nil
        statusMessage = nil
        defer { isConfirming = false }
        do {
            try await pairingService.confirmPairingCode(code)
            statusMessage = "TV signed in."
            codeInput = ""
        } catch {
            errorMessage = "That code is invalid or has expired."
        }
    }
}

#Preview {
    PairTVView(pairingService: FakeTVPairingService())
}
