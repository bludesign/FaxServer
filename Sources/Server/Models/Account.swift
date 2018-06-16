//
//  Account.swift
//  Server
//
//  Created by BluDesign, LLC on 8/3/17.
//

import Foundation
import MongoKitten

struct Account {
    
    // MARK: - Parameters
    
    static let collectionName = "account"
    static var collection: MongoKitten.Collection {
        return MongoProvider.shared.database[collectionName]
    }
}

extension String {
    
    // MARK: - Methods
    
    static func twilioAuthString(_ accountSid: String, authToken: String) throws -> String {
        guard let authString = "\(accountSid):\(authToken)".data(using: .utf8)?.base64EncodedString() else {
            throw ServerAbort(.notFound, reason: "Error creating Twilio authentication")
        }
        return authString
    }
}
