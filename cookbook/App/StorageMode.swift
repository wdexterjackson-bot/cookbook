//
//  StorageMode.swift
//  cookbook
//

import Foundation

/// Whether recipe data lives only on this device or also syncs to the cloud.
///
/// Phase 1 is local-only end to end: every call site checks this, but the
/// app never offers a way to change it yet, and no sync service exists.
/// Phase 2 turns this into a real user setting backed by account state
/// without changing how anything that already checks it behaves.
enum StorageMode {
    case local
    case cloudSynced

    static let current: StorageMode = .local
}
