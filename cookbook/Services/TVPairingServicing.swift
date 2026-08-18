//
//  TVPairingServicing.swift
//  cookbook
//
//  Apple TV phone-pairing sign-in — deliberately server-side only, same
//  reasoning as FriendDiscoveryServicing/EmailProviderLookupServicing: the
//  real adapter calls the requestPairingCode/checkPairingStatus/
//  confirmPairingCode Cloud Functions (functions/tvPairing.js, Admin SDK),
//  never touching the tvPairingRequests collection directly — it has no
//  firestore.rules entry at all, so a direct client read/write couldn't
//  work even if attempted.
//

import Foundation

struct PairingRequest: Equatable {
    var code: String
    var expiresAt: Date
}

enum PairingStatus: Equatable {
    case pending
    /// `token` is non-nil at most once across every poll for a given code
    /// — the server hands it out exactly once (functions/tvPairing.js's
    /// `tokenDelivered` guard).
    case confirmed(token: String?)
    case expired
}

protocol TVPairingServicing {
    /// Called by the signed-out TV to start a new pairing attempt.
    /// `deviceSessionID` is a UUID generated once per screen appearance —
    /// a rate-limit key, not a security boundary.
    func requestPairingCode(deviceSessionID: String) async throws -> PairingRequest
    /// Polled by the TV every few seconds until it stops returning `.pending`.
    func checkPairingStatus(code: String, deviceSessionID: String) async throws -> PairingStatus
    /// Called by the already-signed-in phone once it has the TV's code
    /// (scanned or typed).
    func confirmPairingCode(_ code: String) async throws
}
