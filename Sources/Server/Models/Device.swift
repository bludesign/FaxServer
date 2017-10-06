//
//  Device.swift
//  Server
//
//  Created by BluDesign, LLC on 8/2/17.
//

import Foundation
import MongoKitten

struct Device {
    
    // MARK: - Parameters
    
    static let collectionName = "device"
    static var collection: MongoKitten.Collection {
        return Application.shared.database[collectionName]
    }
}
