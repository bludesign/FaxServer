//
//  Client.swift
//  Server
//
//  Created by BluDesign, LLC on 4/2/17.
//

import Foundation
import MongoKitten

struct Client {
    
    // MARK: - Parameters
    
    static let collectionName = "client"
    static var collection: MongoKitten.Collection {
        return Application.shared.database[collectionName]
    }
}
