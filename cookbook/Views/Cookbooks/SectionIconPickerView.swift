//
//  SectionIconPickerView.swift
//  cookbook
//
//  Every icon in CookbookSectionIconCatalog — full-color entries first,
//  then black, per CookbookConfigurationView's chapter-icon "Change"
//  action. Presented as its own sheet (not nested inside the Chapter
//  Order List/Form section) — a sheet attached to content nested inside a
//  List is unreliable in SwiftUI, the same lesson the ingredient Amount
//  wheel-picker fix already established for this codebase.
//

import SwiftUI

struct SectionIconPickerView: View {
    let currentAssetName: String?
    let onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 114), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(CookbookSectionIconCatalog.allIcons) { icon in
                        Button {
                            onSelect(icon.assetName)
                            dismiss()
                        } label: {
                            VStack(spacing: 4) {
                                Image(icon.assetName)
                                    .resizable()
                                    .scaledToFit()
                                    .padding(12)
                                    .frame(width: 96, height: 96)
                                    .background(Color(white: 0.95))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .overlay {
                                        if icon.assetName == currentAssetName {
                                            RoundedRectangle(cornerRadius: 12)
                                                .strokeBorder(Color.accentColor, lineWidth: 3)
                                        }
                                    }
                                Text(icon.displayName)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(icon.displayName), \(icon.isFullColor ? "full color" : "black")")
                        .accessibilityAddTraits(icon.assetName == currentAssetName ? [.isSelected] : [])
                    }
                }
                .padding()
            }
            .navigationTitle("Choose Icon")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    SectionIconPickerView(currentAssetName: nil, onSelect: { _ in })
}
