//
//  LocationFieldsView.swift
//  cookbook
//
//  Shared between AccountView's Settings location section and the
//  recipe-creation author prompt, so both stay in sync. Meant to be placed
//  directly inside a Form/List Section, not its own container.
//

import SwiftUI

struct LocationFieldsView: View {
    @Binding var city: String
    @Binding var isUS: Bool
    @Binding var stateCode: String
    @Binding var country: String

    var body: some View {
        Picker("Location", selection: $isUS) {
            Text("United States").tag(true)
            Text("Outside the United States").tag(false)
        }
        .pickerStyle(.segmented)

        TextField("City", text: $city)
            #if os(iOS)
            .textInputAutocapitalization(.words)
            #endif
            .autocorrectionDisabled()

        if isUS {
            Picker("State", selection: $stateCode) {
                Text("Select a State").tag("")
                ForEach(USState.all, id: \.code) { state in
                    Text(state.name).tag(state.code)
                }
            }
        } else {
            TextField("Country", text: $country)
                #if os(iOS)
                .textInputAutocapitalization(.words)
                #endif
                .autocorrectionDisabled()
        }
    }
}
