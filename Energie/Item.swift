//
//  Item.swift
//  Energie
//
//  Created by Tobias Florian on 30.09.26.
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
