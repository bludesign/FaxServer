//
//  AuthenticityToken.swift
//  Server
//
//  Created by BluDesign, LLC on 4/2/17.
//

import Foundation
import Vapor
import MongoKitten

struct AuthenticityToken {
    
    // MARK: - Parameters
    
    static let collectionName = "authenticityToken"
    static var collection: MongoKitten.Collection {
        return Application.shared.database[collectionName]
    }
    
    // MARK: - Methods
    
    static func cookieToken() throws -> String {
        let token = try String.tokenEncoded()
        let authenticityToken: Document = [
            "responseType": "cookie",
            "createdAt": Date(),
            "token": token
        ]
        try AuthenticityToken.collection.insert(authenticityToken)
        return token
    }
    
    static func token(responseType: String, clientId: ObjectId, redirectUri: String, scope: String, state: String? = nil, userId: ObjectId? = nil) throws -> String {
        let token = try String.tokenEncoded()
        let authenticityToken: Document = [
            "responseType": responseType,
            "clientId": clientId,
            "redirectUri": redirectUri,
            "scope": scope,
            "state": state,
            "createdAt": Date(),
            "token": token,
            "userId": userId
        ]
        try AuthenticityToken.collection.insert(authenticityToken)
        
        return token
    }
}

extension Request {
    
    // MARK: - Methods
    
    @discardableResult
    func checkAuthenticityToken(oauth: Bool) throws -> (token: String, clientId: ObjectId, redirectUri: String, state: String?, responseType: String, scope: String)? {
        let authenticityTokenString = try data.extract("authenticityToken") as String
        if authenticityTokenString != "none" {
            guard let authenticityToken = try AuthenticityToken.collection.findOne("token" == authenticityTokenString), let authenticityTokenId = authenticityToken.objectId else {
                throw ServerAbort(.notFound, reason: "Authenticity token not found")
            }
            
            let response: (token: String, clientId: ObjectId, redirectUri: String, state: String?, responseType: String, scope: String)?
            let responseType = try authenticityToken.extract("responseType") as String
            if oauth {
                let clientId = try authenticityToken.extract("clientId") as ObjectId
                let redirectUri = try authenticityToken.extract("redirectUri") as String
                let scope = try authenticityToken.extract("scope") as String
                let authenticityState = authenticityToken["state"] as? String
                response = (token: authenticityTokenString, clientId: clientId, redirectUri: redirectUri, state: authenticityState, responseType: responseType, scope: scope)
            } else {
                guard responseType == "cookie" || responseType == "totp" else {
                    throw ServerAbort(.notFound, reason: "Inncorect response type")
                }
                response = nil
            }
            if responseType != "totp" {
                try AuthenticityToken.collection.remove("_id" == authenticityTokenId)
            }
            return response
        } else {
            throw ServerAbort(.notFound, reason: "Not yet implemented")
        }
    }
}
