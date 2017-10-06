//
//  MessageFile.swift
//  Server
//
//  Created by BluDesign, LLC on 9/13/17.
//

import Foundation
import MongoKitten

struct MessageFile {
    
    // MARK: - Parameters
    
    static let collectionName = "messageFile"
    static var collection: MongoKitten.Collection {
        return Application.shared.database[collectionName]
    }
}
