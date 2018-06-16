//
//  AuthenicationMiddleware.swift
//  Server
//
//  Created by BluDesign, LLC on 8/9/17.
//

import Foundation
import Vapor
import MongoKitten

extension HTTPHeaders {
    public var bearerAuthorization: String? {
        get {
            guard let string = self[.authorization].first else { return nil }
            guard let range = string.range(of: "Bearer ") else { return nil }
            let token = string[range.upperBound...]
            return String(token)
        }
        set {
            if let bearer = newValue {
                replaceOrAdd(name: .authorization, value: "Bearer \(bearer)")
            } else {
                remove(name: .authorization)
            }
        }
    }
}

final class AuthenticationStorage: Service {
    var userId: ObjectId? = nil
    var permission: User.Permission? = nil
    
    init() { }
}

final class BasicAuthenticationMiddleware: Middleware, Service {
    
    static var shared = AdminAuthenticationMiddleware()
    
    // MARK: - Methods
    
    func respond(to request: Request, chainingTo next: Responder) throws -> EventLoopFuture<Response> {
        do {
            try request.authentication(allowBasic: true)
        } catch {
            let response = Response(using: request.sharedContainer)
            response.http.headers.replaceOrAdd(name: "WWW-Authenticate", value: "Basic realm=\"Contact Server\" charset=\"UTF-8\"")
            response.http.status = .unauthorized
            return try response.encode(for: request)
        }
        return try next.respond(to: request)
    }
}

final class AdminAuthenticationMiddleware: Middleware, Service {
    
    static var shared = AdminAuthenticationMiddleware()
    
    // MARK: - Methods
    
    func respond(to request: Request, chainingTo next: Responder) throws -> EventLoopFuture<Response> {
        let authentication: Request.Authentication
        do {
            authentication = try request.authentication()
        } catch {
            if request.jsonResponse {
                return try request.statusResponse(status: .unauthorized).encode(for: request)
            }
            return try request.redirect(to: "/user/login?referrer=\(request.http.urlString)").encode(for: request)
        }
        guard authentication.permission.isAdmin else {
            if request.jsonResponse {
                return try request.statusResponse(status: .forbidden).encode(for: request)
            }
            return try request.redirect(to: "\(request.http.url.deletingLastPathComponent().absoluteString)").encode(for: request)
        }
        return try next.respond(to: request)
    }
}

final class AuthenticationMiddleware: Middleware, Service {
    
    static var shared = AuthenticationMiddleware()
    
    // MARK: - Methods
    
    func respond(to request: Request, chainingTo next: Responder) throws -> EventLoopFuture<Response> {
        do {
            try request.authentication()
        } catch {
            if request.jsonResponse {
                return try request.statusResponse(status: .unauthorized).encode(for: request)
            }
            return try request.redirect(to: "/user/login?referrer=\(request.http.urlString)").encode(for: request)
        }
        return try next.respond(to: request)
    }
}

extension Request {
    struct Authentication {
        let userId: ObjectId
        let permission: User.Permission
    }
    
    @discardableResult func authentication(allowBasic: Bool = false) throws -> Authentication {
        let authentication = try privateContainer.make(AuthenticationStorage.self)
        if let userId = authentication.userId, let permission = authentication.permission {
            return Authentication(userId: userId, permission: permission)
        }
        
        let token: String
        if let authorizationCompents = http.headers["Authorization"].first?.components(separatedBy: " "), authorizationCompents.count == 2, let type = authorizationCompents.first, let authorization = authorizationCompents.last {
            if type == "Bearer" {
                token = authorization
            } else if type == "Basic", allowBasic, Admin.settings.basicAuth, let authorizationDecoded = authorization.base64Decoded {
                var compents = authorizationDecoded.components(separatedBy: ":")
                guard compents.count > 1, let email = compents.first else {
                    throw ServerAbort(.unauthorized, reason: "Invalid authentication")
                }
                compents.removeFirst()
                let password = compents.joined(separator: ":")
                let credentials = EmailPassword(email: email, password: password)
                do {
                    let user = try User.login(credentials: credentials)
                    authentication.userId = user.id
                    authentication.permission = user.permission
                    return Authentication(userId: user.id, permission: user.permission)
                } catch {
                    throw ServerAbort(.unauthorized, reason: "Invalid login")
                }
            } else {
                throw ServerAbort(.unauthorized, reason: "No authorization")
            }
        } else if let cookie = http.cookies["Server-Auth"]?.string {
            token = cookie
        } else {
            throw ServerAbort(.unauthorized, reason: "No authorization")
        }
        
        let tokenHash = try MainApplication.makeHash(token)
        guard var accessToken = try AccessToken.collection.findOne("token" == tokenHash) else {
            throw ServerAbort(.unauthorized, reason: "Authorization not found")
        }
        let tokenExpiration = try accessToken.extract("tokenExpires") as Date
        guard Date() < tokenExpiration else {
            throw ServerAbort(.unauthorized, reason: "Authorization is expired")
        }
        let userId = try accessToken.extract("userId") as ObjectId
        if tokenExpiration.timeIntervalSinceReferenceDate - 432000 < Date().timeIntervalSinceReferenceDate, let objectId = accessToken.objectId {
            let expirationDate = Date(timeIntervalSinceNow: AccessToken.cookieExpiresIn)
            accessToken["tokenExpires"] = expirationDate
            accessToken["endOfLife"] = expirationDate
            try AccessToken.collection.update("_id" == objectId, to: accessToken)
        }
        let permission = try accessToken.extractUserPermission("permission")
        authentication.userId = userId
        authentication.permission = permission
        return Authentication(userId: userId, permission: permission)
    }
}
