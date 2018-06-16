//
//  Device.swift
//  Server
//
//  Created by BluDesign, LLC on 8/2/17.
//

import Foundation
import MongoKitten

struct PushDevice {
    
    // MARK: - Parameters
    
    static let collectionName = "pushDevice"
    static var collection: MongoKitten.Collection {
        return MongoProvider.shared.database[collectionName]
    }
}
