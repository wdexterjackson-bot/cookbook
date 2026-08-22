//
//  PickCookbookSheet.swift
//  cookbook
//
//  MessagesView's "which cookbook should this shared recipe go into"
//  prompt — accepting a friend's shared recipe used to silently resolve
//  to whichever cookbook happened to be active, same as Copy-to-Personal
//  from a Community Cookbook; sharing specifically asks first instead.
//

import SwiftUI

struct PickCookbookSheet: View {
    let title: String
    let cookbooks: [Cookbook]
    let onPick: (Cookbook) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if cookbooks.isEmpty {
                    Text("Create a cookbook first, from the Create tab.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(cookbooks) { cookbook in
                        Button {
                            onPick(cookbook)
                            dismiss()
                        } label: {
                            Text(cookbook.title)
                        }
                    }
                }
            }
            .navigationTitle(title)
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
    PickCookbookSheet(title: "Add to Cookbook", cookbooks: [], onPick: { _ in })
}
