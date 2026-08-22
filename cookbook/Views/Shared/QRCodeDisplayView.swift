//
//  QRCodeDisplayView.swift
//  cookbook
//
//  Reused for both "Share My QR Code" (friend code, on the user's own
//  profile) and the group code on CommunityCookbookManageView's settings — same
//  presentation, different payload.
//

import SwiftUI
import UniformTypeIdentifiers

/// What ShareLink actually shares — our own controlled PNG bytes rather
/// than SwiftUI's own `Image: Transferable` conformance. See
/// QRCodeImageGenerator.pngData's own doc comment for why: a saved copy
/// of this needs to stay pixel-exact to still be scannable, which
/// `Image`'s own transfer representation doesn't guarantee.
private struct QRCodeShareFile: Transferable {
    let pngData: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { $0.pngData }
    }
}

struct QRCodeDisplayView: View {
    let payload: QRCodePayload
    let title: String
    let subtitle: String

    @Environment(\.dismiss) private var dismiss

    private var qrImage: Image? {
        QRCodeImageGenerator.image(for: payload.stringValue)
    }

    private var qrPNGData: Data? {
        QRCodeImageGenerator.pngData(for: payload.stringValue)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let qrImage {
                    qrImage
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 260)
                        .padding()
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: PotluckMetrics.cardCornerRadius))
                        .potluckCardShadow()
                } else {
                    ContentUnavailableView("Couldn't Generate QR Code", systemImage: "qrcode")
                }

                Text(title)
                    .font(.potluckHeadline(20))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                #if !os(tvOS)
                if let qrImage, let qrPNGData {
                    ShareLink(
                        item: QRCodeShareFile(pngData: qrPNGData),
                        preview: SharePreview(title, image: qrImage)
                    ) {
                        Label("Share QR Code", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 8)
                }
                #endif

                Spacer()
            }
            .padding(.top, 32)
            .background(Color.potluckCream)
            .navigationTitle("")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    QRCodeDisplayView(
        payload: .friend(id: "preview-user"),
        title: "Your Friend Code",
        subtitle: "Friends can scan this to send you a friend request."
    )
}
