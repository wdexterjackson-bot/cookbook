//
//  QuantityWheelPicker.swift
//  cookbook
//
//  Replaces free-text decimal entry for an ingredient amount — most home
//  cooks think in whole numbers plus a common measuring-cup/spoon fraction
//  ("1 1/2 cups"), not decimals ("1.5"), and typing a fraction into a
//  decimal-only field silently failed to parse before this existed.
//

import SwiftUI

struct QuantityWheelPicker: View {
    @Binding var quantity: WheelQuantity

    var body: some View {
        HStack(spacing: 0) {
            Picker("Whole number", selection: $quantity.whole) {
                ForEach(0...100, id: \.self) { number in
                    Text("\(number)").tag(number)
                }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)
            .labelsHidden()
            .accessibilityLabel("Whole number amount")

            Picker("Fraction", selection: $quantity.fraction) {
                ForEach(CookingFraction.allCases) { fraction in
                    Text(fraction.displayText.isEmpty ? "—" : fraction.displayText).tag(fraction)
                }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)
            .labelsHidden()
            .accessibilityLabel("Fraction amount")
        }
    }
}

#Preview {
    @Previewable @State var quantity = WheelQuantity(whole: 1, fraction: .oneHalf)
    VStack {
        Text(quantity.displayText.isEmpty ? "No amount" : quantity.displayText)
            .font(.headline)
        QuantityWheelPicker(quantity: $quantity)
            .frame(height: 160)
    }
}
