//
//  QuantityWheelPicker.swift
//  cookbook
//
//  Replaces free-text decimal entry for an ingredient amount — most home
//  cooks think in whole numbers plus a common measuring-cup/spoon fraction
//  ("1 1/2 cups"), not decimals ("1.5"), and typing a fraction into a
//  decimal-only field silently failed to parse before this existed.
//
//  The whole-number side is a text field, not a wheel — a wheel has to cap
//  somewhere, and 0...100 silently ate any ingredient calling for more than
//  100 of a unit (280g, 200g flour) since a value outside the wheel's range
//  just can't be represented/selected (2026-08-15 feedback). The fraction
//  side stays a wheel: it only ever needs the 10 fixed eighths/thirds a
//  measuring cup actually prints, where a wheel is faster than typing.
//

import SwiftUI

struct QuantityWheelPicker: View {
    @Binding var quantity: WheelQuantity

    /// Clamped to non-negative — a free-text field can't otherwise stop
    /// someone typing "-5", which WheelQuantity/CookingFraction never
    /// expect (decimalValue assumes whole >= 0).
    private var wholeBinding: Binding<Int> {
        Binding(
            get: { quantity.whole },
            set: { quantity.whole = max(0, $0) }
        )
    }

    var body: some View {
        HStack(spacing: 16) {
            TextField("0", value: wholeBinding, format: .number)
                .font(.title.weight(.medium))
                .multilineTextAlignment(.center)
                #if os(iOS)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                #endif
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Whole number amount")

            Picker("Fraction", selection: $quantity.fraction) {
                ForEach(CookingFraction.allCases) { fraction in
                    Text(fraction.displayText.isEmpty ? "—" : fraction.displayText).tag(fraction)
                }
            }
            // .wheel is iOS-only — unavailable on tvOS (no drag-to-scroll
            // paradigm there) and on macOS (not a supported PickerStyle).
            // Both fall back to their platform default Picker presentation.
            #if os(iOS)
            .pickerStyle(.wheel)
            #endif
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
