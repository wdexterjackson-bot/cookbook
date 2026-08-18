//
//  FirebaseTVPairingService.swift
//  cookbook
//

import FirebaseFunctions
import Foundation

enum TVPairingServiceError: Error {
    case malformedResponse
}

extension TVPairingServiceError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .malformedResponse: return "Something went wrong. Try again."
        }
    }
}

final class FirebaseTVPairingService: TVPairingServicing {
    private let functions = Functions.functions()

    func requestPairingCode(deviceSessionID: String) async throws -> PairingRequest {
        let callable = functions.httpsCallable("requestPairingCode")
        let result = try await callable.call(["deviceSessionID": deviceSessionID])
        guard let data = result.data as? [String: Any],
              let code = data["code"] as? String,
              let expiresAtMillis = data["expiresAt"] as? Double else {
            throw TVPairingServiceError.malformedResponse
        }
        return PairingRequest(code: code, expiresAt: Date(timeIntervalSince1970: expiresAtMillis / 1000))
    }

    func checkPairingStatus(code: String, deviceSessionID: String) async throws -> PairingStatus {
        let callable = functions.httpsCallable("checkPairingStatus")
        let result = try await callable.call(["code": code, "deviceSessionID": deviceSessionID])
        guard let data = result.data as? [String: Any], let status = data["status"] as? String else {
            throw TVPairingServiceError.malformedResponse
        }
        switch status {
        case "pending": return .pending
        case "expired": return .expired
        case "confirmed": return .confirmed(token: data["token"] as? String)
        default: throw TVPairingServiceError.malformedResponse
        }
    }

    func confirmPairingCode(_ code: String) async throws {
        let callable = functions.httpsCallable("confirmPairingCode")
        _ = try await callable.call(["code": code])
    }
}
