//
//  Message.swift
//  Server
//
//  Created by BluDesign, LLC on 8/25/17.
//

import Foundation
import MongoKitten

struct Message {
    
    // MARK: - Parameters
    
    static let collectionName = "message"
    static var collection: MongoKitten.Collection {
        return Application.shared.database[collectionName]
    }
}
