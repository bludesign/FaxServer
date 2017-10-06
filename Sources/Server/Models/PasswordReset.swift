//
//  PasswordReset.swift
//  Server
//
//  Created by BluDesign, LLC on 8/4/17.
//

import Foundation
import MongoKitten

struct PasswordReset {
    
    // MARK: - Parameters
    
    static let collectionName = "passwordReset"
    static var collection: MongoKitten.Collection {
        return Application.shared.database[collectionName]
    }
    
    // MARK: - Methods
    
    static func resetToken(_ userId: ObjectId, referrer: String) throws -> String {
        let token = try String.tokenEncoded()
        let authenticityToken: Document = [
            "createdAt": Date(),
            "userId": userId,
            "referrer": referrer,
            "token": token
        ]
        try PasswordReset.collection.insert(authenticityToken)
        return token
    }
}
