//
//  AccessToken.swift
//  Server
//
//  Created by BluDesign, LLC on 4/2/17.
//

import Foundation
import Vapor
import MongoKitten
import Crypto

struct AccessToken {
    
    // MARK: - Parameters
    
    private static let expiresIn: Double = 43200
    private static let renewalTime: Double = 5184000
    static let cookieExpiresIn: Double = 604800
    
    static let collectionName = "accessToken"
    static var collection: MongoKitten.Collection {
        return MongoProvider.shared.database[collectionName]
    }
    
    // MARK: - Methods
    
    static func token(userId: ObjectId, permission: User.Permission, clientId: ObjectId, source: String, scope: String) throws -> (token: String, refreshToken: String, expiresIn: Double) {
        let token = try String.tokenEncoded()
        let tokenHash = try MainApplication.makeHash(token)
        let refreshToken = try String.tokenEncoded()
        let refreshTokenHash = try MainApplication.makeHash(refreshToken)
        let accessToken: Document = [
            "userId": userId,
            "clientId": clientId,
            "createdAt": Date(),
            "tokenExpires": Date(timeIntervalSinceNow: AccessToken.expiresIn),
            "endOfLife": Date(timeIntervalSinceNow: AccessToken.renewalTime + AccessToken.expiresIn),
            "token": tokenHash,
            "refreshToken": refreshTokenHash,
            "source": source,
            "scope": scope,
            "permission": permission.rawValue
        ]
        try AccessToken.collection.insert(accessToken)
        return (token: token, refreshToken: refreshToken, expiresIn: AccessToken.expiresIn)
    }
    
    static func cookieToken(userId: ObjectId, permission: User.Permission) throws -> (token: String, expires: Date) {
        let token = try String.tokenEncoded()
        let tokenHash = try MainApplication.makeHash(token)
        let expires = Date(timeIntervalSinceNow: AccessToken.cookieExpiresIn)
        let accessToken: Document = [
            "userId": userId,
            "createdAt": Date(),
            "tokenExpires": expires,
            "endOfLife": expires,
            "token": tokenHash,
            "source": "cookie",
            "permission": permission.rawValue
        ]
        try AccessToken.collection.insert(accessToken)
        return (token: token, expires: expires)
    }
    
    static func refreshToken(refreshToken: String) throws -> (token: String, expiresIn: Double, scope: String) {
        let refreshTokenHash = try MainApplication.makeHash(refreshToken)
        guard var accessToken = try AccessToken.collection.findOne("refreshToken" == refreshTokenHash), let accessTokenId = accessToken.objectId else {
            throw ServerAbort(.unauthorized, reason: "Refresh token not found")
        }
        let scope = try accessToken.extract("scope") as String
        let token = try String.tokenEncoded()
        let tokenHash = try MainApplication.makeHash(token)
        accessToken["tokenExpires"] = Date(timeIntervalSinceNow: AccessToken.expiresIn)
        accessToken["endOfLife"] = Date(timeIntervalSinceNow: AccessToken.renewalTime + AccessToken.expiresIn)
        accessToken["token"] = tokenHash
        try AccessToken.collection.update("_id" == accessTokenId, to: accessToken)
        
        return (token: token, expiresIn: AccessToken.expiresIn, scope: scope)
    }
}
