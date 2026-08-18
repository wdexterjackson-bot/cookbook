//
//  PlatformCompatibility.swift
//  cookbook
//
//  A handful of SwiftUI APIs this app uses are only available on some of
//  its three platforms (iOS/macOS/tvOS) and are hard compile errors on the
//  others, not silent no-ops — these helpers centralize the availability
//  gating so call sites don't have to repeat the same #if block.
//

import SwiftUI

/// Mirrors `TextInputAutocapitalization`'s cases — that real type doesn't
/// exist on macOS at all (not even as an unused parameter type), so a
/// shared, always-available stand-in is what makes a single call-site API
/// possible across all three platforms.
enum PlatformAutocapitalization {
    case never, words, sentences, characters
}

#if !os(macOS)
private extension PlatformAutocapitalization {
    var native: TextInputAutocapitalization {
        switch self {
        case .never: .never
        case .words: .words
        case .sentences: .sentences
        case .characters: .characters
        }
    }
}
#endif

extension View {
    /// `.textInputAutocapitalization` is unavailable on macOS (no
    /// soft-keyboard autocapitalization concept there) — iOS and tvOS
    /// both support it.
    @ViewBuilder
    func autocapitalizationIfAvailable(_ autocapitalization: PlatformAutocapitalization) -> some View {
        #if os(macOS)
        self
        #else
        self.textInputAutocapitalization(autocapitalization.native)
        #endif
    }

    /// Forces a List's delete/move affordances to always be active,
    /// without a separate Edit button toggle — an iOS-only concern.
    /// macOS Lists don't use `\.editMode` at all (drag-to-reorder and
    /// delete work through other means there), and tvOS has no
    /// swipe/edit-button paradigm either.
    @ViewBuilder
    func alwaysEditingOnIOS() -> some View {
        #if os(iOS)
        self.environment(\.editMode, .constant(.active))
        #else
        self
        #endif
    }
}
