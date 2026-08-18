//
//  FakeTVPairingService.swift
//  cookbook
//

import Foundation

final class FakeTVPairingService: TVPairingServicing {
    var codesByDeviceSessionID: [String: String] = [:]
    var statusesByCode: [String: PairingStatus] = [:]
    var confirmedCodes: [String] = []
    var requestError: Error?
    var confirmError: Error?

    func requestPairingCode(deviceSessionID: String) async throws -> PairingRequest {
        if let requestError { throw requestError }
        let code = "FAKE\(codesByDeviceSessionID.count)"
        codesByDeviceSessionID[deviceSessionID] = code
        statusesByCode[code] = .pending
        return PairingRequest(code: code, expiresAt: .now.addingTimeInterval(300))
    }

    func checkPairingStatus(code: String, deviceSessionID: String) async throws -> PairingStatus {
        statusesByCode[code] ?? .expired
    }

    func confirmPairingCode(_ code: String) async throws {
        if let confirmError { throw confirmError }
        confirmedCodes.append(code)
        statusesByCode[code] = .confirmed(token: "fake-token-\(code)")
    }
}
