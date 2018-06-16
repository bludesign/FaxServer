//
//  User.swift
//  Server
//
//  Created by BluDesign, LLC on 3/24/17.
//

import Foundation
import Vapor
import MongoKitten
import Crypto
import Leaf

struct User {
    
    // MARK: - Parameters
    
    static let collectionName = "user"
    static var collection: MongoKitten.Collection {
        return MongoProvider.shared.database[collectionName]
    }
    static var logoutCookie: HTTPCookies {
        return ["Server-Auth": HTTPCookieValue(string: "", expires: Date(), domain: Admin.settings.domainHostname ?? "127.0.0.1", isSecure: MainApplication.shared.application.environment.isRelease && Admin.settings.secureCookie, isHTTPOnly: true, sameSite: .strict)]
    }
    
    private var totpToken: String?
    private var totpCode: String?
    var id: ObjectId
    var permission: Permission
    var totpRequired: Bool {
        return totpToken != nil && totpCode == nil
    }
    
    enum Permission: Int, CustomStringConvertible, Codable {
        case readOnly = 0
        case regular = 1
        case admin = 2
        
        var description: String {
            switch self {
            case .readOnly: return "Read Only"
            case .regular: return "Regular"
            case .admin: return "Admin"
            }
        }
        
        var isAdmin: Bool {
            return self == .admin
        }
    }
    
    // MARK: - Life Cycle
    
    init(_ id: ObjectId, permission: Permission, totpToken: String? = nil, totpCode: String? = nil) {
        self.id = id
        self.permission = permission
        self.totpToken = totpToken
        self.totpCode = totpCode
    }
    
    // MARK: - Methods
    
    func accessToken() throws -> (token: String, expires: Date) {
        if let totpToken = totpToken {
            guard let totpCode = totpCode else {
                throw ServerAbort.init(.unauthorized, reason: "2FA authencation code required")
            }
            
            let oldKey = try TOTP.generate(key: totpToken, timeInterval: Date().timeIntervalSince1970 - 25)
            let key = try TOTP.generate(key: totpToken)
            guard key == totpCode || oldKey == totpCode else {
                throw ServerAbort.init(.unauthorized, reason: "2FA authencation code invalid")
            }
        }
        return try AccessToken.cookieToken(userId: id, permission: permission)
    }
    
    func authenticityToken(clientId: ObjectId, redirectUri: String, scope: String, state: String? = nil) throws -> String {
        return try AuthenticityToken.token(responseType: "totp", clientId: clientId, redirectUri: redirectUri, scope: scope, state: state, userId: id)
    }
    
    func authenticityToken(host: String?) throws -> String {
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
            "responseType": "totp",
            "createdAt": Date(),
            "token": token,
            "userId": id,
            "hostName": hostName
        ]
        try AuthenticityToken.collection.insert(authenticityToken)
        return token
    }
    
    func cookie(domain: String) throws -> HTTPCookies {
        let token = try accessToken()
        return ["Server-Auth": HTTPCookieValue(string: token.token, expires: token.expires, domain: domain, isSecure: MainApplication.shared.application.environment.isRelease && Admin.settings.secureCookie, isHTTPOnly: true, sameSite: .strict)]
    }
    
    func authorizationCode(redirectUri: String, clientId: ObjectId, scope: String, state: String? = nil) throws -> String {
        if let totpToken = totpToken {
            guard let totpCode = totpCode else {
                throw ServerAbort.init(.unauthorized, reason: "2FA authencation code required")
            }
            
            let oldKey = try TOTP.generate(key: totpToken, timeInterval: Date().timeIntervalSince1970 - 25)
            let key = try TOTP.generate(key: totpToken)
            guard key == totpCode || oldKey == totpCode else {
                throw ServerAbort.init(.unauthorized, reason: "2FA authencation code invalid")
            }
        }
        let code = try String.tokenEncoded()
        let authorizationCode: Document = [
            "code": code,
            "redirectUri": redirectUri,
            "clientId": clientId,
            "createdAt": Date(),
            "userId": id,
            "state": state,
            "scope": scope
        ]
        try AuthorizationCode.collection.insert(authorizationCode)
        return code.urlQueryPercentEncodedPlus
    }
}

extension User {
    
    // MARK: - Methods
    
    @discardableResult static func register(credentials: Credentials, permission: Permission = .admin) throws -> User {
        var user: User?
        
        switch credentials {
        case let credentials as EmailPassword:
            guard try User.collection.findOne("email" == credentials.email) == nil else {
                throw ServerAbort(.found, reason: "Email address is already in use")
            }
            let document: Document = [
                "email": credentials.email,
                "password": try BCrypt.hash(credentials.password),
                "permission": permission.rawValue
            ]
            guard let userId = try User.collection.insert(document) as? ObjectId else {
                throw ServerAbort(.internalServerError, reason: "Error creating user")
            }
            user = User(userId, permission: permission)
        default:
            throw ServerAbort(.methodNotAllowed, reason: "Credentials not supported")
        }
        
        if let user = user {
            return user
        } else {
            throw ServerAbort(.forbidden, reason: "Incorrect credentials")
        }
    }
    
    static func login(credentials: Credentials) throws -> User {
        var user: User?
        
        switch credentials {
        case let credentials as EmailPassword:
            guard let userDocument = try User.collection.findOne("email" == credentials.email), let userId = userDocument.objectId else {
                throw ServerAbort(.forbidden, reason: "No account with email: \(credentials.email) found")
            }
            let password = try userDocument.extract("password") as String
            let permission = try userDocument.extractUserPermission("permission")
            guard try BCrypt.verify(credentials.password, created: password) else {
                throw ServerAbort(.forbidden, reason: "Incorrect credentials")
            }
            if userDocument["totpActivated"] as? Bool == true {
                let totpToken = try userDocument.extract("totpToken") as String
                user = User(userId, permission: permission, totpToken: totpToken)
            } else {
                user = User(userId, permission: permission)
            }
        case let credentials as Totp:
            guard let authenticityDocument = try AuthenticityToken.collection.findOne("token" == credentials.authenticityToken), let authenticityTokenId = authenticityDocument.objectId else {
                throw ServerAbort(.forbidden, reason: "No authenticity token found")
            }
            let responseType = try authenticityDocument.extract("responseType") as String
            let userId = try authenticityDocument.extract("userId") as ObjectId
            try AuthenticityToken.collection.remove("_id" == authenticityTokenId)
            guard responseType == "totp" else {
                throw ServerAbort(.forbidden, reason: "Invalid authenticity token")
            }
            guard let userDocument = try User.collection.findOne("_id" == userId) else {
                throw ServerAbort(.forbidden, reason: "No account found")
            }
            let permission = try userDocument.extractUserPermission("permission")
            let totpToken = try userDocument.extract("totpToken") as String
            user = User(userId, permission: permission, totpToken: totpToken, totpCode: credentials.code)
        default:
            throw ServerAbort(.methodNotAllowed, reason: "Credentials not supported")
        }
        
        if let user = user {
            return user
        } else {
            throw ServerAbort(.notFound, reason: "No user object")
        }
    }
    
    static func forgotPassword(email: String, referrer: String, host: String, redirect: String?, request: Request, promise: EventLoopPromise<ServerResponse>) throws {
        guard let document = try User.collection.findOne("email" == email), let objectId = document.objectId else {
            throw ServerAbort(.forbidden, reason: "No account with email: \(email) found")
        }
        let resetToken = try PasswordReset.resetToken(objectId, referrer: referrer)
        let url = Admin.settings.domain ?? "http://\(host)"
        
        let leaf = try request.make(LeafRenderer.self)
        let context: [String: String] = [
            "url": "\(url)/user/forgot-password?token=\(resetToken)"
        ]
        let view = leaf.render("forgotPasswordEmail", context)
        view.do { view in
            do {
                try Email.send(subject: "Reset Password", to: email, htmlBody: view.data, redirect: redirect, request: request, promise: promise)
            } catch let error {
                promise.fail(error: error)
            }
            }.catch { error in
                promise.fail(error: error)
        }
    }
    
    static func resetPassword(credentials: Credentials) throws -> User {
        var userDocument: Document?
        
        switch credentials {
        case let credentials as EmailPassword:
            guard var document = try User.collection.findOne("email" == credentials.email) else {
                throw ServerAbort(.found, reason: "No user account for email address")
            }
            document["password"] = try BCrypt.hash(credentials.password)
            userDocument = document
        default:
            throw ServerAbort(.methodNotAllowed, reason: "Credentials not supported")
        }
        
        if let userDocument = userDocument {
            guard let userId = userDocument.objectId else {
                throw ServerAbort(.found, reason: "No user account for email address")
            }
            let permission = try userDocument.extractUserPermission("permission")
            try User.collection.update("_id" == userId, to: userDocument)
            if userDocument["totpActivated"] as? Bool == true {
                let totpToken = try userDocument.extract("totpToken") as String
                return User(userId, permission: permission, totpToken: totpToken)
            } else {
                return User(userId, permission: permission)
            }
        } else {
            throw ServerAbort(.forbidden, reason: "Incorrect credentials")
        }
    }
}
