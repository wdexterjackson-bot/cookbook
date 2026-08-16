//
//  ConversionToolView.swift
//  cookbook
//
//  A standard measurement-unit converter — cups to ml, ounces to grams,
//  the usual "any online conversion tool" shape — reached from More.
//  Volume and weight are two separate pickers, never a single combined
//  list, since converting between them needs an ingredient's density
//  (MeasurementConverter deliberately doesn't attempt that).
//

import SwiftUI

struct ConversionToolView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var category: ConversionCategory = .volume
    @State private var fromUnit: MeasurementUnit = MeasurementUnit.volumeUnits[3] // Cup
    @State private var toUnit: MeasurementUnit = MeasurementUnit.volumeUnits[7] // Milliliter
    @State private var inputText = "1"

    private var inputValue: Double {
        Double(inputText) ?? 0
    }

    private var resultValue: Double {
        MeasurementConverter.convert(inputValue, from: fromUnit, to: toUnit)
    }

    private var resultText: String {
        resultValue.formatted(.number.precision(.fractionLength(0...3)))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Category", selection: $category) {
                        ForEach(ConversionCategory.allCases) { category in
                            Text(category.rawValue).tag(category)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: category) { _, newCategory in
                        fromUnit = newCategory.units[0]
                        toUnit = newCategory.units[1]
                    }
                }

                Section("From") {
                    TextField("Amount", text: $inputText)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    Picker("Unit", selection: $fromUnit) {
                        ForEach(category.units) { unit in
                            Text("\(unit.name) (\(unit.abbreviation))").tag(unit)
                        }
                    }
                }

                Section {
                    Button {
                        swap(&fromUnit, &toUnit)
                    } label: {
                        Label("Swap Units", systemImage: "arrow.up.arrow.down")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }

                Section("To") {
                    Picker("Unit", selection: $toUnit) {
                        ForEach(category.units) { unit in
                            Text("\(unit.name) (\(unit.abbreviation))").tag(unit)
                        }
                    }
                    LabeledContent("Result") {
                        Text("\(resultText) \(toUnit.abbreviation)")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Color.potluckTomato)
                    }
                }
            }
            .potluckHiddenScrollBackground()
            .background(Color.potluckCream)
            .navigationTitle("Conversion Tool")
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
    ConversionToolView()
}
