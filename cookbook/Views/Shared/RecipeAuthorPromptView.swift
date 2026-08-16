//
//  RecipeAuthorPromptView.swift
//  cookbook
//
//  Shown at recipe-save time whenever the signed-in user's profile has no
//  name set — dismissable (swiping away should save as Anonymous; the
//  presenting view's .sheet(onDismiss:) is what handles that, not this
//  view), and lets the user fill in their name/location right here rather
//  than needing to go to Settings first. Shared between
//  CreateEditRecipeView (single-recipe save) and ImportRecipesFileView
//  (bulk import, resolved once for the whole batch).
//

import SwiftUI

struct RecipeAuthorPromptView: View {
    let onSaveWithName: (String, UserLocation?) -> Void
    let onSaveAnonymous: () -> Void

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var city = ""
    @State private var isUS = true
    @State private var stateCode = ""
    @State private var country = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("First Name", text: $firstName)
                        #if os(iOS)
                        .textInputAutocapitalization(.words)
                        #endif
                    TextField("Last Name", text: $lastName)
                        #if os(iOS)
                        .textInputAutocapitalization(.words)
                        #endif
                } header: {
                    Text("Credit This Recipe To")
                } footer: {
                    Text("Saved to your profile so future recipes use it automatically — you can change it anytime in Settings.")
                }

                Section("Location (Optional)") {
                    LocationFieldsView(city: $city, isUS: $isUS, stateCode: $stateCode, country: $country)
                }
            }
            .potluckHiddenScrollBackground()
            .background(Color.potluckCream)
            .navigationTitle("Add Your Name?")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Save as Anonymous", action: onSaveAnonymous)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save My Name") {
                        let name = "\(firstName.trimmingCharacters(in: .whitespacesAndNewlines)) \(lastName.trimmingCharacters(in: .whitespacesAndNewlines))"
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        let trimmedCity = city.trimmingCharacters(in: .whitespacesAndNewlines)
                        let location: UserLocation? = trimmedCity.isEmpty ? nil : UserLocation(
                            city: trimmedCity,
                            isUS: isUS,
                            stateCode: isUS ? (stateCode.isEmpty ? nil : stateCode) : nil,
                            country: isUS ? nil : country.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                        onSaveWithName(name, location)
                    }
                    .disabled(
                        firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }
            }
        }
    }
}
