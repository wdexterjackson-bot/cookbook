//
//  Color+Hex.swift
//  cookbook
//
//  Cookbook.coverColorHex round-trips as a plain hex string (simplest
//  Codable/SwiftData-friendly representation); this is the only place
//  that converts to/from a real Color.
//

import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

extension Color {
    init(hex: String) {
        let sanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        var value: UInt64 = 0
        Scanner(string: sanitized).scanHexInt64(&value)
        let red = Double((value & 0xFF0000) >> 16) / 255
        let green = Double((value & 0x00FF00) >> 8) / 255
        let blue = Double(value & 0x0000FF) / 255
        self.init(red: red, green: green, blue: blue)
    }

    var hexString: String {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        #if os(iOS)
        UIColor(self).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        #elseif os(macOS)
        let platformColor = NSColor(self).usingColorSpace(.deviceRGB) ?? NSColor(self)
        platformColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        #endif

        return String(format: "%02X%02X%02X", Int(red * 255), Int(green * 255), Int(blue * 255))
    }
}
