//
//  PotluckStepper.swift
//  cookbook
//
//  SwiftUI's own Stepper is unavailable on tvOS entirely (it relies on a
//  press-and-hold-to-accelerate gesture with no tvOS remote equivalent) —
//  this mirrors its `value:in:step:label:` API so call sites don't change
//  per platform, falling back to a plain -/+ Button pair on tvOS.
//

import SwiftUI

struct PotluckStepper<Value: Strideable, Label: View>: View {
    @Binding var value: Value
    let range: ClosedRange<Value>
    let step: Value.Stride
    @ViewBuilder let label: () -> Label

    var body: some View {
        #if os(tvOS)
        HStack {
            label()
            Spacer()
            Button {
                value = max(range.lowerBound, value.advanced(by: -step))
            } label: {
                Image(systemName: "minus.circle")
            }
            .disabled(value <= range.lowerBound)
            Button {
                value = min(range.upperBound, value.advanced(by: step))
            } label: {
                Image(systemName: "plus.circle")
            }
            .disabled(value >= range.upperBound)
        }
        #else
        Stepper(value: $value, in: range, step: step, label: label)
        #endif
    }
}
