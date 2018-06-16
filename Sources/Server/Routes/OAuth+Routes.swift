//
//  OAuth+Routes.swift
//  Server
//
//  Created by BluDesign, LLC on 4/2/17.
//

import Foundation
import Vapor
import MongoKitten
import Crypto

struct OAuthRouter {
    
    init(router: Router) {
        router.get("authorize", use: getAuthorize)
        router.post("login", use: postLogin)
        router.post("access_token", use: postAccessToken)
    }
    
    // MARK: GET authorize
    func getAuthorize(_ request: Request) throws -> Future<ServerResponse> {
        return request.globalAsync { promise in
            struct FormData: Codable {
                let response_type: String?
                let scope: String?
                let state: String?
                let redirect_uri: String?
                let client_id: ObjectId
            }
            let formData = try request.query.decode(FormData.self)
            
            let responseType = formData.response_type ?? "code"
            guard responseType == "code" else {
                throw ServerAbort(.notFound, reason: "Response type must be code")
            }
            
            let scope = formData.scope ?? "user"
            guard scope == "user" else {
                throw ServerAbort(.notFound, reason: "Scope must be user")
            }
            
            guard let client = try FaxClient.collection.findOne("_id" == formData.client_id) else {
                throw ServerAbort(.notFound, reason: "Client not found.")
            }
            
            guard let clientRedirectUri = client["redirectUri"] as? String else {
                throw ServerAbort(.notFound, reason: "Missing redirect URI")
            }
            let redirectUri = formData.redirect_uri ?? clientRedirectUri
            guard redirectUri == clientRedirectUri else {
                throw ServerAbort(.notFound, reason: "Incorrect redirect URI")
            }
            
            let token = try AuthenticityToken.token(responseType: responseType, clientId: formData.client_id, redirectUri: redirectUri, scope: scope, state: formData.state)
            let context = TemplateData.dictionary([
                "authenticityToken": .string(token),
                "redirectUri": .string(redirectUri),
                "referrer": .string("none"),
                "unauthorized": .bool((try? request.query.get(Bool.self, at: "unauthorized")) == true),
                "passwordReset": .bool((try? request.query.get(Bool.self, at: "passwordReset")) == true),
            ])
            return promise.submit(try request.renderEncoded("login", context))
        }
    }
    
    // MARK: POST login
    func postLogin(_ request: Request) throws -> Future<ServerResponse> {
        return request.globalAsync { promise in
            struct FormData: Codable {
                let action: String
                let code: String?
                let email: String?
                let password: String?
                let redirectUri: String?
            }
            let formData = try request.content.syncDecode(FormData.self)
            
            guard let checkedAuthenticityToken = try? request.checkOauthAuthenticityToken(), let authenticityToken = checkedAuthenticityToken else {
                if let redirectUri = formData.redirectUri {
                    return promise.submit(try request.redirectEncoded(to: "\(redirectUri)?result=failed"))
                }
                throw ServerAbort(.requestTimeout, reason: "Authenticity token expired try login again")
            }
            
            let credentials: Credentials
            if formData.action == "totp" {
                let code = try formData.code.unwrapped("code")
                credentials = Totp(code: code, authenticityToken: authenticityToken.token)
            } else {
                let email = try formData.email.unwrapped("email")
                let password = try formData.password.unwrapped("password")
                credentials = EmailPassword(email: email, password: password)
            }
            let encodedCode: String
            do {
                let user = try User.login(credentials: credentials)
                if user.totpRequired {
                    let token = try user.authenticityToken(clientId: authenticityToken.clientId, redirectUri: authenticityToken.redirectUri, scope: authenticityToken.scope, state: authenticityToken.state)
                    let context = TemplateData.dictionary([
                        "authenticityToken": .string(token),
                        "referrer": .string("none"),
                        "unauthorized": .bool((try? request.query.get(Bool.self, at: "unauthorized")) == true),
                    ])
                    return promise.submit(try request.renderEncoded("totp", context))
                }
                encodedCode = try user.authorizationCode(redirectUri: authenticityToken.redirectUri, clientId: authenticityToken.clientId, scope: authenticityToken.scope, state: authenticityToken.state)
            } catch let error {
                Logger.error("Error: \(error)")
                let token = try AuthenticityToken.token(responseType: authenticityToken.responseType, clientId: authenticityToken.clientId, redirectUri: authenticityToken.redirectUri, scope: authenticityToken.scope, state: authenticityToken.state)
                let context = TemplateData.dictionary([
                    "authenticityToken": .string(token),
                    "referrer": .string("none"),
                    "unauthorized": .bool(true),
                ])
                return promise.submit(try request.renderEncoded("login", context))
            }
            
            if let state = authenticityToken.state {
                return promise.succeed(result: request.serverRedirect(to: "\(authenticityToken.redirectUri)?code=\(encodedCode)&state=\(state)"))
            } else {
                return promise.succeed(result: request.serverRedirect(to: "\(authenticityToken.redirectUri)?code=\(encodedCode)"))
            }
        }
    }
    
    // MARK: POST access_token
    func postAccessToken(_ request: Request) throws -> Future<ServerResponse> {
        return request.globalAsync { promise in
            struct FormData: Codable {
                let grant_type: String
                let client_id: ObjectId?
                let client_secret: String?
                let refresh_token: String?
                let code: String?
                let redirectUri: String?
            }
            let formData = try request.content.syncDecode(FormData.self)
            
            let clientId: ObjectId
            let clientSecretString: String
            if let authorization = request.http.headers["Authorization"].first?.components(separatedBy: " ").last?.base64Decoded?.components(separatedBy: ":"), authorization.count == 2, let clientIdString = authorization.first, let clientSecret = authorization.last {
                clientId = try ObjectId(clientIdString)
                clientSecretString = clientSecret
            } else {
                clientId = try formData.client_id.unwrapped("client_id")
                clientSecretString = try formData.client_secret.unwrapped("client_secret")
            }
            
            guard let client = try FaxClient.collection.findOne("_id" == clientId) else {
                throw ServerAbort(.unauthorized, reason: "Client not found")
            }
            guard let clientSecret = clientSecretString.removingPercentEncoding else {
                throw ServerAbort(.unauthorized, reason: "Client secret not found")
            }
            let databaseSecret = try client.extract("secret") as String
            guard try BCrypt.verify(clientSecret, created: databaseSecret) else {
                throw ServerAbort(.forbidden, reason: "Incorrect credentials")
            }
            
            if formData.grant_type == "authorization_code" {
                let code = try formData.code.unwrapped("code")
                guard let authorizationCode = try AuthorizationCode.collection.findOne("code" == code), let authorizationCodeId = authorizationCode.objectId else {
                    throw ServerAbort(.unauthorized, reason: "Authorization code \(code) not found")
                }
                let authorizationClientId = try authorizationCode.extract("clientId") as ObjectId
                
                guard clientId == authorizationClientId else {
                    throw ServerAbort(.badRequest, reason: "Client ID does not match authorization")
                }
                if let redirectUri = formData.redirectUri, authorizationCode["redirectUri"] as? String != redirectUri {
                    throw ServerAbort(.badRequest, reason: "Redirect URI does not match authorization")
                }
                let userId = try authorizationCode.extract("userId") as ObjectId
                guard let user = try User.collection.findOne("_id" == userId, projecting: [
                    "_id",
                    "permission"
                ]) else {
                    throw ServerAbort(.notFound, reason: "User not found")
                }
                let permission = try user.extractUserPermission("permission")
                let scope = try authorizationCode.extract("scope") as String
                
                try AuthorizationCode.collection.remove("_id" == authorizationCodeId)
                let token = try AccessToken.token(userId: userId, permission: permission, clientId: clientId, source: "oauth", scope: scope)
                
                let json: [String: Codable] = [
                    "access_token": token.token,
                    "refresh_token": token.refreshToken,
                    "expires_in": token.expiresIn,
                    "token_type": "Bearer",
                    "scope": scope
                ]
                return promise.submit(try request.jsonEncoded(json: json))
            } else if formData.grant_type == "refresh_token" {
                let refreshToken = try formData.refresh_token.unwrapped("refresh_token")
                let token = try AccessToken.refreshToken(refreshToken: refreshToken)
                
                let json: [String: Codable] = [
                    "access_token": token.token,
                    "expires_in": token.expiresIn,
                    "token_type": "Bearer",
                    "scope": token.scope
                ]
                return promise.submit(try request.jsonEncoded(json: json))
            } else {
                throw ServerAbort(.badRequest, reason: "Invalid grant type")
            }
        }
    }
}
