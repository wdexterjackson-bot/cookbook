//
//  AddFriendView.swift
//  cookbook
//
//  Three discovery methods, per FEATURE 2's design (email search, plus
//  QR by camera and by image file): exact-email search (silent no-match
//  either way — see FriendDiscoveryServicing), a live camera scan
//  (VisionKit, iOS-only), and picking an existing QR code image (Vision's
//  static-image barcode detection — no camera needed, so this one also
//  works on macOS) for when a friend shared their code as a picture
//  instead of showing it in person. All three funnel into the same
//  FriendsServicing.sendFriendRequest call, enforced by the normal rules.
//

import SwiftUI
import UniformTypeIdentifiers

struct AddFriendView: View {
    let friendsService: FriendsServicing
    let friendDiscoveryService: FriendDiscoveryServicing

    @Environment(AccountState.self) private var accountState
    @Environment(\.dismiss) private var dismiss
    @State private var emailInput = ""
    @State private var isSearching = false
    @State private var foundUser: DiscoveredUser?
    @State private var searchAttempted = false
    @State private var isSendingRequest = false
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
                    TextField("Friend's Email", text: $emailInput)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        #endif
                        .autocorrectionDisabled()
                    Button("Search") {
                        Task { await search() }
                    }
                    .disabled(isSearching || emailInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } footer: {
                    Text("Friends can also add you via your QR code — from your own profile.")
                }

                #if os(iOS) || os(macOS)
                Section {
                    #if os(iOS)
                    Button {
                        isPresentingScanner = true
                    } label: {
                        Label("Scan a Friend's QR Code", systemImage: "qrcode.viewfinder")
                    }
                    #endif
                    Button {
                        isPresentingImagePicker = true
                    } label: {
                        Label("Choose a QR Code Image", systemImage: "photo")
                    }
                }
                #endif

                if isSearching {
                    ProgressView()
                }
                if searchAttempted, !isSearching {
                    if let foundUser {
                        Section {
                            Text(foundUser.displayName ?? "Found a match")
                            Button("Send Friend Request") {
                                Task { await sendRequest(to: foundUser.userID) }
                            }
                            .disabled(isSendingRequest)
                        }
                    } else {
                        Text("No findable user with that email.")
                            .foregroundStyle(.secondary)
                    }
                }
                if let statusMessage {
                    Text(statusMessage).foregroundStyle(.green)
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .navigationTitle("Add Friend")
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
                    Task { await handleScannedPayload(payload) }
                }
            }
            #endif
            #if os(iOS) || os(macOS)
            .fileImporter(isPresented: $isPresentingImagePicker, allowedContentTypes: [.image]) { result in
                handleImageFileSelection(result)
            }
            #endif
        }
    }

    private func search() async {
        let email = emailInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty else { return }
        isSearching = true
        errorMessage = nil
        statusMessage = nil
        foundUser = nil
        defer {
            isSearching = false
            searchAttempted = true
        }
        do {
            foundUser = try await friendDiscoveryService.findUser(byEmail: email)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func sendRequest(to userID: String) async {
        guard let currentUserID = accountState.currentUserID else { return }
        isSendingRequest = true
        errorMessage = nil
        defer { isSendingRequest = false }
        do {
            try await friendsService.sendFriendRequest(from: currentUserID, to: userID)
            statusMessage = "Friend request sent."
            foundUser = nil
            // Otherwise searchAttempted staying true with foundUser now nil
            // would render "No findable user with that email." right above
            // the success message — that line (and the email field it was
            // for) belong to the search that's now done with.
            searchAttempted = false
            emailInput = ""
        } catch FriendsServiceError.alreadyFriends {
            errorMessage = "You're already friends."
        } catch {
            errorMessage = error.localizedDescription
        }
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
            Task { await handleScannedPayload(payload) }
        }
    }
    #endif

    private func handleScannedPayload(_ payload: QRCodePayload) async {
        guard let currentUserID = accountState.currentUserID, case .friend(let friendUserID) = payload else {
            errorMessage = "That QR code isn't a friend code."
            return
        }
        guard friendUserID != currentUserID else {
            errorMessage = "That's your own QR code."
            return
        }
        errorMessage = nil
        do {
            try await friendsService.sendFriendRequest(from: currentUserID, to: friendUserID)
            statusMessage = "Friend request sent."
        } catch FriendsServiceError.alreadyFriends {
            errorMessage = "You're already friends."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    AddFriendView(friendsService: InMemoryFriendsService(), friendDiscoveryService: FakeFriendDiscoveryService())
        .environment(AccountState(authService: FakeAuthService()))
}
