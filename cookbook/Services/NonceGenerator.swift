//
//  NonceGenerator.swift
//  cookbook
//
//  Sign in with Apple's replay protection: Apple gets the SHA256 hash of a
//  random nonce, Firebase gets the raw nonce back to verify against Apple's
//  signed token. Standard pattern for bridging ASAuthorization to Firebase.
//

import CryptoKit
import Foundation

enum NonceGenerator {
    static func randomNonce(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length

        while remainingLength > 0 {
            var randomBytes = [UInt8](repeating: 0, count: 16)
            let status = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
            precondition(status == errSecSuccess, "Unable to generate secure random nonce bytes")

            for byte in randomBytes where remainingLength > 0 {
                if byte < charset.count {
                    result.append(charset[Int(byte)])
                    remainingLength -= 1
                }
            }
        }
        return result
    }

    static func sha256(_ input: String) -> String {
        let hashed = SHA256.hash(data: Data(input.utf8))
        return hashed.map { String(format: "%02x", $0) }.joined()
    }
}
