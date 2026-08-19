//
//  RecipeFilterSheet.swift
//  cookbook
//

import SwiftUI

struct RecipeFilterSheet: View {
    @Binding var criteria: RecipeFilterCriteria
    let availableOptions: RecipeFilterOptions
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Favorites Only", isOn: $criteria.favoritesOnly)
                }

                if !availableOptions.courses.isEmpty {
                    picker("Course", selection: $criteria.course, options: availableOptions.courses)
                }
                if !availableOptions.cuisines.isEmpty {
                    picker("Cuisine", selection: $criteria.cuisine, options: availableOptions.cuisines)
                }
                if !availableOptions.tags.isEmpty {
                    picker("Tag", selection: $criteria.tag, options: availableOptions.tags)
                }
                if !availableOptions.dietaryLabels.isEmpty {
                    picker("Dietary Label", selection: $criteria.dietaryLabel, options: availableOptions.dietaryLabels)
                }
                if !availableOptions.allergens.isEmpty {
                    picker("Exclude Allergen", selection: $criteria.excludedAllergen, options: availableOptions.allergens)
                }

                Section {
                    Button("Clear All Filters", role: .destructive) {
                        criteria.clearFilters()
                    }
                }
            }
            .navigationTitle("Filters")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func picker(_ title: String, selection: Binding<String?>, options: [String]) -> some View {
        Picker(title, selection: selection) {
            Text("Any").tag(String?.none)
            ForEach(options, id: \.self) { option in
                Text(option).tag(String?.some(option))
            }
        }
    }
}

#Preview {
    RecipeFilterSheet(
        criteria: .constant(RecipeFilterCriteria()),
        availableOptions: RecipeFilterOptions(recipes: [])
    )
}
