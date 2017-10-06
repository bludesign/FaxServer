//
//  FaxFile.swift
//  Server
//
//  Created by BluDesign, LLC on 7/1/17.
//

import Foundation
import MongoKitten

struct FaxFile {
    
    // MARK: - Parameters
    
    static let collectionName = "faxFile"
    static var collection: MongoKitten.Collection {
        return Application.shared.database[collectionName]
    }
}
