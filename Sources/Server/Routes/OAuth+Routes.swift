//
//  OAuth+Routes.swift
//  Server
//
//  Created by BluDesign, LLC on 4/2/17.
//

import Foundation
import Vapor
import MongoKitten
import BCrypt

struct OAuth {
    
    // MARK: - Methods
    
    static func routes(_ drop: Droplet, _ group: RouteBuilder) {
        
        // MARK: Get Authorization Code
        group.get("authorize") { request in
            let responseType = request.data["response_type"]?.string ?? "code"
            guard responseType == "code" else {
                throw ServerAbort(.notFound, reason: "Response type must be code")
            }
            
            let scope = request.data["scope"]?.string ?? "user"
            guard scope == "user" else {
                throw ServerAbort(.notFound, reason: "Scope must be user")
            }
            
            let state = request.data["state"]?.string
            
            let redirectUri = try request.data.extract("redirect_uri") as String
            let clientId = try request.data.extract("client_id") as ObjectId
            guard let client = try Client.collection.findOne("_id" == clientId) else {
                throw ServerAbort(.notFound, reason: "Client not found.")
            }
            
            guard client["redirectUri"] as? String == redirectUri else {
                throw ServerAbort(.notFound, reason: "Incorrect redirect URI")
            }
            
            let token = try AuthenticityToken.token(responseType: responseType, clientId: clientId, redirectUri: redirectUri, scope: scope, state: state)
            return try drop.view.make("login", [
                "authenticityToken": token,
                "referrer": "none"
            ])
        }
        
        // MARK: Login
        group.post("login") { request in
            guard let authenticityToken = try request.checkAuthenticityToken(oauth: true) else {
                throw ServerAbort(.notFound, reason: "Authenticity token check failed")
            }
            
            let action = try request.data.extract("action") as String
            let credentials: Credentials
            if action == "totp" {
                let code = try request.data.extract("code") as String
                credentials = Totp(code: code, authenticityToken: authenticityToken.token)
            } else {
                let email = try request.data.extract("email") as String
                let password = try request.data.extract("password") as String
                credentials = EmailPassword(email: email, password: password)
            }
            let encodedCode: String
            do {
                let user = try User.login(credentials: credentials)
                if user.totpRequired {
                    let token = try user.authenticityToken(clientId: authenticityToken.clientId, redirectUri: authenticityToken.redirectUri, scope: authenticityToken.scope, state: authenticityToken.state)
                    return try drop.view.make("totp", [
                        "authenticityToken": token,
                        "referrer": request.data["referrer"]?.string ?? "none"
                    ])
                }
                encodedCode = try user.authorizationCode(redirectUri: authenticityToken.redirectUri, clientId: authenticityToken.clientId, scope: authenticityToken.scope, state: authenticityToken.state)
            } catch {
                let token = try AuthenticityToken.token(responseType: authenticityToken.responseType, clientId: authenticityToken.clientId, redirectUri: authenticityToken.redirectUri, scope: authenticityToken.scope, state: authenticityToken.state)
                return try drop.view.make("login", [
                    "authenticityToken": token,
                    "referrer": "none",
                    "unauthorized": true
                ])
            }

            if let state = authenticityToken.state {
                return Response(redirect: "\(authenticityToken.redirectUri)?code=\(encodedCode)&state=\(state)")
            } else {
                return Response(redirect: "\(authenticityToken.redirectUri)?code=\(encodedCode)")
            }
        }
        
        // MARK: Get Access Token
        group.post("access_token") { request in
            let grantType = try request.data.extract("grant_type") as String
            let clientId: ObjectId
            let clientSecretString: String
            if let authorization = request.headers["Authorization"]?.components(separatedBy: " ").last?.makeBytes().base64Decoded.makeString().components(separatedBy: ":"), authorization.count == 2, let clientIdString = authorization.first, let clientSecret = authorization.last {
                clientId = try ObjectId(clientIdString)
                clientSecretString = clientSecret
            } else {
                clientId = try request.data.extract("client_id") as ObjectId
                clientSecretString = try request.data.extract("client_secret") as String
            }
            guard let client = try Client.collection.findOne("_id" == clientId) else {
                throw ServerAbort(.unauthorized, reason: "Client not found")
            }
            guard let clientSecret = clientSecretString.removingPercentEncoding else {
                throw ServerAbort(.unauthorized, reason: "Client secret not found")
            }
            let databaseSecret = try client.extract("secret") as String
            guard try BCrypt.Hash.verify(message: clientSecret, matches: databaseSecret) else {
                throw ServerAbort(.forbidden, reason: "Incorrect credentials")
            }
            
            if grantType == "authorization_code" {
                let code = try request.data.extract("code") as String
                let redirectUri = try request.data.extract("redirect_uri") as String
                guard let authorizationCode = try AuthorizationCode.collection.findOne("code" == code), let authorizationCodeId = authorizationCode.objectId else {
                    throw ServerAbort(.unauthorized, reason: "Authorization code \(code) not found")
                }
                let authorizationClientId = try authorizationCode.extract("clientId") as ObjectId
                
                guard clientId == authorizationClientId else {
                    throw ServerAbort(.badRequest, reason: "Client ID does not match authorization")
                }
                guard authorizationCode["redirectUri"] as? String == redirectUri else {
                    throw ServerAbort(.badRequest, reason: "Redirect URI does not match authorization")
                }
                let userId = try authorizationCode.extract("userId") as ObjectId
                let scope = try authorizationCode.extract("scope") as String
                
                try AuthorizationCode.collection.remove("_id" == authorizationCodeId)
                let token = try AccessToken.token(userId: userId, clientId: clientId, source: "oauth", scope: scope)
                
                return try JSON(node: [
                    "access_token": token.token,
                    "refresh_token": token.refreshToken,
                    "expires_in": token.expiresIn,
                    "token_type": "Bearer",
                    "scope": scope
                ]).makeResponse()
            } else if grantType == "refresh_token" {
                let refreshToken = try request.data.extract("refresh_token") as String
                let token = try AccessToken.refreshToken(refreshToken: refreshToken)
                
                return try JSON(node: [
                    "access_token": token.token,
                    "expires_in": token.expiresIn,
                    "token_type": "Bearer",
                    "scope": token.scope
                ]).makeResponse()
            } else {
                throw ServerAbort(.badRequest, reason: "Invalid grant type")
            }
        }
    }
}
