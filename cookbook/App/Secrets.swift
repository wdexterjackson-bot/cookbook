//
//  Secrets.swift
//  cookbook
//
//  Reads cookbook/Secrets.plist — gitignored, per-developer, never
//  committed, same pattern as GoogleService-Info.plist. Missing keys fail
//  loudly at the call site rather than silently degrading, since a search
//  feature silently returning nothing is worse than a clear startup error.
//

import Foundation

enum Secrets {
    enum SecretsError: Error {
        case missingPlist
        case missingKey(String)
    }

    private static let values: [String: Any] = {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else {
            return [:]
        }
        return plist
    }()

    static func string(forKey key: String) throws -> String {
        guard let value = values[key] as? String, !value.isEmpty else {
            throw SecretsError.missingKey(key)
        }
        return value
    }

    static var spoonacularAPIKey: String {
        get throws { try string(forKey: "SpoonacularAPIKey") }
    }
}
