//
//  AuthorizationCode.swift
//  Server
//
//  Created by BluDesign, LLC on 4/2/17.
//

import Foundation
import MongoKitten

struct AuthorizationCode {
    
    // MARK: - Parameters
    
    static let collectionName = "authorizationCode"
    static var collection: MongoKitten.Collection {
        return Application.shared.database[collectionName]
    }
}
