//
//  DietaryPreferencesView.swift
//  cookbook
//

import SwiftUI

struct DietaryPreferencesView: View {
    @Binding var diet: DietPreference
    @Binding var excludedAllergens: Set<AllergenPreference>
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Default Diet") {
                    Picker("Diet", selection: $diet) {
                        ForEach(DietPreference.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section {
                    ForEach(AllergenPreference.allCases) { allergen in
                        Toggle(allergen.label, isOn: allergenBinding(for: allergen))
                    }
                } header: {
                    Text("Exclude Allergens")
                } footer: {
                    Text("Applied automatically to Discover searches — you can still override per search.")
                }
            }
            .navigationTitle("Dietary Preferences")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        DietaryPreferencesStore.setCurrent(DietaryPreferences(defaultDiet: diet, excludedAllergens: excludedAllergens))
                        dismiss()
                    }
                }
            }
        }
    }

    private func allergenBinding(for allergen: AllergenPreference) -> Binding<Bool> {
        Binding(
            get: { excludedAllergens.contains(allergen) },
            set: { isExcluded in
                if isExcluded {
                    excludedAllergens.insert(allergen)
                } else {
                    excludedAllergens.remove(allergen)
                }
            }
        )
    }
}

#Preview {
    DietaryPreferencesView(diet: .constant(.vegan), excludedAllergens: .constant([.peanut]))
}
