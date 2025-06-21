//
//  Item.swift
//  neto
//
//  Created by Sergii Solianyk on 21/06/2025.
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
