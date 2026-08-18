//
//  QRCodePayload.swift
//  cookbook
//
//  A plain, unsigned, client-decoded string — no server round-trip needed
//  to interpret a scanned code, so this works phone-to-phone with no
//  network. Deliberately guessable (anyone who knows a groupID/userID
//  could construct the same string without ever seeing the real code) —
//  confirmed acceptable because scanning only ever *sends a request*,
//  identical in effect to finding the same group/person via search; it
//  grants no access by itself. The actual join/friend-request call still
//  goes through GroupsServicing/FriendsServicing, enforced by the normal
//  rules. Don't reuse this payload format for anything that grants access
//  directly.
//

import Foundation

enum QRCodePayload: Equatable {
    case group(id: String)
    case friend(id: String)

    var stringValue: String {
        switch self {
        case .group(let id): return "cookbook:group:\(id)"
        case .friend(let id): return "cookbook:friend:\(id)"
        }
    }

    init?(stringValue: String) {
        let parts = stringValue.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "cookbook" else { return nil }
        let id = String(parts[2])
        guard !id.isEmpty else { return nil }
        switch parts[1] {
        case "group": self = .group(id: id)
        case "friend": self = .friend(id: id)
        default: return nil
        }
    }
}
