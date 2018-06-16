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
        return MongoProvider.shared.database[collectionName]
    }
    
    // MARK: - Methods
    
    static func cookieToken(host: String?) throws -> String {
        let hostName: String
        if Admin.settings.secureCookie == false, let host = host {
            hostName = host
        } else if let host = Admin.settings.domainHostname {
            hostName = host
        } else {
            hostName = "127.0.0.1"
        }
        let token = try String.tokenEncoded()
        let authenticityToken: Document = [
            "responseType": "cookie",
            "createdAt": Date(),
            "token": token,
            "hostName": hostName
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
    func checkOauthAuthenticityToken() throws -> (token: String, clientId: ObjectId, redirectUri: String, state: String?, responseType: String, scope: String)?  {
        let authenticityTokenString = try get(at: "authenticityToken") as String
        guard authenticityTokenString != "none" else {
            throw ServerAbort(.badRequest, reason: "Authenticity token invalid")
        }
        guard let authenticityToken = try AuthenticityToken.collection.findOne("token" == authenticityTokenString), let authenticityTokenId = authenticityToken.objectId else {
            throw ServerAbort(.badRequest, reason: "Authenticity token not found")
        }
        
        let response: (token: String, clientId: ObjectId, redirectUri: String, state: String?, responseType: String, scope: String)?
        let responseType = try authenticityToken.extract("responseType") as String
        guard responseType == "code" || responseType == "totp" else {
            throw ServerAbort(.badRequest, reason: "Inncorect response type")
        }
        
        let clientId = try authenticityToken.extract("clientId") as ObjectId
        let redirectUri = try authenticityToken.extract("redirectUri") as String
        let scope = try authenticityToken.extract("scope") as String
        let authenticityState = authenticityToken["state"] as? String
        response = (token: authenticityTokenString, clientId: clientId, redirectUri: redirectUri, state: authenticityState, responseType: responseType, scope: scope)
        
        if responseType != "totp" {
            try AuthenticityToken.collection.remove("_id" == authenticityTokenId)
        }
        return response
    }
    
    @discardableResult
    func checkCookieAuthenticityToken() throws -> String {
        let authenticityTokenString = try get(at: "authenticityToken") as String
        guard authenticityTokenString != "none" else {
            throw ServerAbort(.badRequest, reason: "Authenticity token invalid")
        }
        guard let authenticityToken = try AuthenticityToken.collection.findOne("token" == authenticityTokenString), let authenticityTokenId = authenticityToken.objectId else {
            throw ServerAbort(.badRequest, reason: "Authenticity token not found")
        }
        let hostName = try authenticityToken.extract("hostName") as String
        let responseType = try authenticityToken.extract("responseType") as String
        guard responseType == "cookie" || responseType == "totp" else {
            throw ServerAbort(.badRequest, reason: "Inncorect response type")
        }
        if responseType != "totp" {
            try AuthenticityToken.collection.remove("_id" == authenticityTokenId)
        }
        return hostName
    }
}
