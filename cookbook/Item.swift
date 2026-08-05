//
//  Item.swift
//  cookbook
//
//  Created by Dexter Jackson on 8/5/26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
