//
//  QuotaTracker.swift
//  cookbook
//
//  Spoonacular's free tier is 50 points/day — real enough that the UI
//  needs to know when it's running low and fall back to cache/TheMealDB
//  rather than erroring hard. Reads the X-API-Quota-Left header Spoonacular
//  returns on every response (confirmed live during planning).
//

import Foundation

enum QuotaTracker {
    private static let remainingKey = "com.vibeapp.cookbook.spoonacularQuotaLeft"
    private static let updatedAtKey = "com.vibeapp.cookbook.spoonacularQuotaUpdatedAt"
    private static let lowThreshold = 5.0

    static func record(from response: HTTPURLResponse) {
        guard let header = response.value(forHTTPHeaderField: "X-API-Quota-Left"),
              let remaining = Double(header)
        else { return }
        UserDefaults.standard.set(remaining, forKey: remainingKey)
        UserDefaults.standard.set(Date.now, forKey: updatedAtKey)
    }

    static var remainingPoints: Double? {
        guard UserDefaults.standard.object(forKey: remainingKey) != nil else { return nil }
        return UserDefaults.standard.double(forKey: remainingKey)
    }

    static var lastUpdatedAt: Date? {
        UserDefaults.standard.object(forKey: updatedAtKey) as? Date
    }

    /// True once we have evidence quota is running low. Unknown (never
    /// called Spoonacular yet) reads as "not low" — optimistic default.
    static var isLow: Bool {
        guard let remaining = remainingPoints else { return false }
        return remaining < lowThreshold
    }
}
