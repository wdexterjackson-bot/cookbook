//
//  DiscountCodePromo.swift
//  cookbook
//
//  The seam for discount-code validity, same shape/reasoning as
//  LaunchCreditPromo (EntitlementGranting.swift) — a plain enum of
//  constants, not a service, since there's nothing here that needs a
//  network round-trip to check. The real enforcement is the matching
//  hardcoded check in firestore.rules; this client-side copy exists only
//  so an invalid/expired code gets a clean, specific error message instead
//  of an opaque Firestore permission-denied.
//

import Foundation

enum DiscountCodePromo {
    /// The one currently-valid discount code, redeemable once per account
    /// for a free Annual Pro Membership credit.
    static let validCode = "7595SLEDGERD"

    /// The code stops being redeemable after this date (valid through
    /// 2028-12-31) — must match the deadline hardcoded in firestore.rules
    /// exactly.
    static let redemptionDeadline = makeUTCDate(year: 2029, month: 1, day: 1)

    static func isValid(_ code: String, on date: Date = .now) -> Bool {
        code == validCode && date < redemptionDeadline
    }

    private static func makeUTCDate(year: Int, month: Int, day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return calendar.date(from: components)!
    }
}
