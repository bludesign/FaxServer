//
//  User.swift
//  Server
//
//  Created by BluDesign, LLC on 3/24/17.
//

import Foundation
import Vapor
import MongoKitten
import BCrypt
import Cookies
import Crypto
import SMTP

struct User {
    
    // MARK: - Parameters
    
    static let collectionName = "user"
    static var collection: MongoKitten.Collection {
        return Application.shared.database[collectionName]
    }
    static var logoutCookie: Cookie {
        return Cookie(name: "Server-Auth", value: "", expires: Date(), domain: Admin.settings.domainHostname ?? "127.0.0.1", secure: Application.shared.drop.config.environment == .production, httpOnly: true, sameSite: .strict)
    }
    
    private var totpToken: String?
    private var totpCode: String?
    var id: ObjectId
    var totpRequired: Bool {
        return totpToken != nil && totpCode == nil
    }
    
    // MARK: - Life Cycle
    
    init(_ id: ObjectId, totpToken: String? = nil, totpCode: String? = nil) {
        self.id = id
        self.totpToken = totpToken
        self.totpCode = totpCode
    }
    
    // MARK: - Methods
    
    func accessToken() throws -> (token: String, expires: Date) {
        if let totpToken = totpToken {
            guard let totpCode = totpCode else {
                throw ServerAbort.init(.unauthorized, reason: "2FA authencation code required")
            }
            let key = try TOTP.generate(key: totpToken)
            guard key == totpCode else {
                throw ServerAbort.init(.unauthorized, reason: "2FA authencation code invalid")
            }
        }
        return try AccessToken.cookieToken(userId: id)
    }
    
    func authenticityToken(clientId: ObjectId, redirectUri: String, scope: String, state: String? = nil) throws -> String {
        return try AuthenticityToken.token(responseType: "totp", clientId: clientId, redirectUri: redirectUri, scope: scope, state: state, userId: id)
    }
    
    func authenticityToken() throws -> String {
        let token = try String.tokenEncoded()
        let authenticityToken: Document = [
            "responseType": "totp",
            "createdAt": Date(),
            "token": token,
            "userId": id
        ]
        try AuthenticityToken.collection.insert(authenticityToken)
        return token
    }
    
    func cookie(domain: String) throws -> Cookie {
        let token = try accessToken()
        let hostName: String
        if Admin.settings.secureCookie == false, let url = URL(string: domain), let host = url.host {
            hostName = host
        } else if let host = Admin.settings.domainHostname {
            hostName = host
        } else {
            hostName = "127.0.0.1"
        }
        return Cookie(name: "Server-Auth", value: token.token, expires: token.expires, domain: hostName, secure: Application.shared.drop.config.environment == .production && Admin.settings.secureCookie, httpOnly: true, sameSite: .strict)
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
    
    static func register(credentials: Credentials) throws -> User {
        var user: User?
        
        switch credentials {
        case let credentials as EmailPassword:
            guard try User.collection.findOne("email" == credentials.email) == nil else {
                throw ServerAbort(.found, reason: "Email address is already in use")
            }
            let document: Document = [
                "email": credentials.email,
                "password": try BCrypt.Hash.make(message: credentials.password, with: Salt()).makeString()
            ]
            guard let userId = try User.collection.insert(document) as? ObjectId else {
                throw ServerAbort(.notFound, reason: "Error creating user")
            }
            user = User(userId)
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
            guard let document = try User.collection.findOne("email" == credentials.email), let objectId = document.objectId else {
                throw ServerAbort(.forbidden, reason: "No account with email: \(credentials.email) found")
            }
            let password = try document.extract("password") as String
            guard try BCrypt.Hash.verify(message: credentials.password, matches: password) else {
                throw ServerAbort(.forbidden, reason: "Incorrect credentials")
            }
            if document["totpActivated"] as? Bool == true {
                let totpToken = try document.extract("totpToken") as String
                user = User(objectId, totpToken: totpToken)
            } else {
                user = User(objectId)
            }
        case let credentials as Totp:
            guard let authenticityDocument = try AuthenticityToken.collection.findOne("token" == credentials.authenticityToken), let authenticityTokenId = authenticityDocument.objectId else {
                throw ServerAbort(.forbidden, reason: "No authenticity token found")
            }
            let responseType = try authenticityDocument.extract("responseType") as String
            let objectId = try authenticityDocument.extract("userId") as ObjectId
            try AuthenticityToken.collection.remove("_id" == authenticityTokenId)
            guard responseType == "totp" else {
                throw ServerAbort(.forbidden, reason: "Invalid authenticity token")
            }
            guard let document = try User.collection.findOne("_id" == objectId) else {
                throw ServerAbort(.forbidden, reason: "No account found")
            }
            let totpToken = try document.extract("totpToken") as String
            user = User(objectId, totpToken: totpToken, totpCode: credentials.code)
        default:
            throw ServerAbort(.methodNotAllowed, reason: "Credentials not supported")
        }
        
        if let user = user {
            return user
        } else {
            throw ServerAbort(.notFound, reason: "No user object")
        }
    }
    
    static func forgotPassword(email: String, referrer: String) throws {
        guard let document = try User.collection.findOne("email" == email), let objectId = document.objectId else {
            throw ServerAbort(.forbidden, reason: "No account with email: \(email) found")
        }
        let resetToken = try PasswordReset.resetToken(objectId, referrer: referrer)
        
        guard let url = Admin.settings.domain else {
            throw ServerAbort(.notFound, reason: "No host URL set in settings")
        }
        let data: NodeRepresentable = [
            "url": "\(url)/user/forgot-password?token=\(resetToken)"
        ]
        do {
            let content = try Application.shared.drop.view.make("forgotPasswordEmail", data).data.makeString()
            try Email(from: Admin.settings.mailgunFromEmail, to: email, subject: "Reset Password", body: EmailBody(type: .html, content: content)).send()
        } catch let error {
            Logger.error("Error Sending Email: \(error)")
        }
    }
    
    static func resetPassword(credentials: Credentials) throws -> User {
        var userDocument: Document?
        
        switch credentials {
        case let credentials as EmailPassword:
            guard var document = try User.collection.findOne("email" == credentials.email) else {
                throw ServerAbort(.found, reason: "No user account for email address")
            }
            document["password"] = try BCrypt.Hash.make(message: credentials.password, with: Salt()).makeString()
            userDocument = document
        default:
            throw ServerAbort(.methodNotAllowed, reason: "Credentials not supported")
        }
        
        if let userDocument = userDocument {
            guard let userId = userDocument.objectId else {
                throw ServerAbort(.found, reason: "No user account for email address")
            }
            try User.collection.update("_id" == userId, to: userDocument)
            if userDocument["totpActivated"] as? Bool == true {
                let totpToken = try userDocument.extract("totpToken") as String
                return User(userId, totpToken: totpToken)
            } else {
                return User(userId)
            }
        } else {
            throw ServerAbort(.forbidden, reason: "Incorrect credentials")
        }
    }
}
