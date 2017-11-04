//
//  User+Routes.swift
//  Server
//
//  Created by BluDesign, LLC on 4/2/17.
//

import Foundation
import Vapor
import MongoKitten
import Crypto
import BCrypt

extension User {
    
    // MARK: - Methods
    
    static func routes(_ drop: Droplet, _ group: RouteBuilder) {
        let protected = group.grouped([AuthenticationMiddleware.shared])
        
        // MARK: Get Users
        protected.get { request in
            let skip = request.data["skip"]?.int ?? 0
            let limit = min(100, request.data["limit"]?.int ?? 100)
            let documents = try User.collection.find(sortedBy: ["email": .ascending], projecting: [
                "password": false,
                "totpToken": false
            ], skipping: skip, limitedTo: limit, withBatchSize: limit)
            if request.jsonResponse {
                guard request.userId != nil else {
                    return Response(jsonStatus: .unauthorized)
                }
                return try documents.makeResponse()
            } else {
                guard request.userId != nil else {
                    return Response(redirect: "/user/login?referrer=/user")
                }
                
                var tableData: String = ""
                for document in documents {
                    guard let email = document["email"], let id = document.objectId else {
                        continue
                    }
                    let totpActivated = document["totpActivated"] as? Bool ?? false
                    let badge = (totpActivated ? "success" : "danger")
                    let string = "<tr onclick=\"location.href='/user/\(id.hexString)'\"><td>\(email)</td><td><span class=\"badge badge-\(badge)\">\((totpActivated ? "Enabled" : "Disabled"))</span></td></tr>"
                    tableData.append(string)
                }
                return try drop.view.make("users", [
                    "tableData": tableData,
                    "emailTaken": request.data["emailTaken"] != nil
                ])
            }
        }
        
        // MARK: Update User
        protected.post(":objectId") { request in
            let objectId = try request.parameters.extract("objectId") as ObjectId
            
            guard var document = try User.collection.findOne("_id" == objectId) else {
                throw ServerAbort(.notFound, reason: "User not found")
            }
            
            if request.data["action"]?.string == "delete" {
                try User.collection.remove("_id" == objectId)
                if request.jsonResponse {
                    return Response(jsonStatus: .ok)
                }
                return Response(redirect: "/user")
            }
            
            if let email = try? request.data.extract("email") as String {
                document["email"] = email
            }
            if let password = try? request.data.extract("password") as String {
                document["password"] = try BCrypt.Hash.make(message: password, with: Salt()).makeString()
            }
            
            try User.collection.update("_id" == objectId, to: document, upserting: true)
            
            if request.jsonResponse {
                return Response(jsonStatus: .ok)
            }
            return Response(redirect: "/user")
        }
        
        // MARK: Get User
        protected.get(":objectId") { request in
            let objectId = try request.parameters.extract("objectId") as ObjectId
            
            guard let document = try User.collection.findOne("_id" == objectId, projecting: [
                "password": false,
                "totpToken": false
            ]) else {
                throw ServerAbort(.notFound, reason: "User not found")
            }
            
            if request.jsonResponse {
                return try document.makeResponse()
            } else {
                let email = try document.extract("email") as String
                let totpActivated = try? document.extract("totpActivated") as Bool
                return try drop.view.make("user", [
                    "userId": objectId.hexString,
                    "email": email,
                    "totpActivated": totpActivated ?? false
                ])
            }
        }
        
        // MARK: Update User TOTP
        protected.post(":objectId", "totp") { request in
            let objectId = try request.parameters.extract("objectId") as ObjectId
            
            guard var document = try User.collection.findOne("_id" == objectId) else {
                throw ServerAbort(.notFound, reason: "User not found")
            }
            
            if request.data["action"]?.string == "deactivate" {
                document["totpToken"] = nil
                document["totpActivated"] = false
                try User.collection.update("_id" == objectId, to: document)
                if request.jsonResponse {
                    return Response(jsonStatus: .ok)
                }
                return Response(redirect: "/user/\(objectId.hexString)")
            } else if request.data["action"]?.string == "activate" || request.data["action"]?.string == "resetToken" {
                let token = try TOTP.randomToken()
                document["totpToken"] = token
                document["totpActivated"] = false
                try User.collection.update("_id" == objectId, to: document)
                if request.jsonResponse {
                    return Response(jsonStatus: .ok)
                } else {
                    let email = try document.extract("email") as String
                    let token = try document.extract("totpToken") as String
                    return try drop.view.make("user", [
                        "userId": objectId.hexString,
                        "email": email,
                        "verify": true,
                        "totpToken": token
                    ])
                }
            } else if request.data["action"]?.string == "verify" {
                let token = try document.extract("totpToken") as String
                let key = try TOTP.generate(key: token)
                let code = try request.data.extract("code") as String
                
                guard key == code else {
                    throw ServerAbort(.unauthorized, reason: "Invalid token")
                }
                
                document["totpActivated"] = true
                try User.collection.update("_id" == objectId, to: document)
                if request.jsonResponse {
                    return Response(jsonStatus: .ok)
                }
                return Response(redirect: "/user/\(objectId.hexString)")
            }
            return Response(redirect: "/user/\(objectId.hexString)")
        }
        
        // MARK: Create User
        protected.post { request in
            let email = try request.data.extract("email") as String
            let password = try request.data.extract("password") as String
            
            do {
                let cookie = try User.register(credentials: EmailPassword(email: email, password: password)).cookie(domain: request.uri.domain)
                let referrer = request.data["referrer"]?.string ?? "/user"
                let response = Response(redirect: (referrer == "none" ? "/user" : referrer))
                if referrer != "/user" {
                    response.cookies.insert(cookie)
                }
                if request.jsonResponse {
                    return Response(jsonStatus: .ok)
                }
                return response
            } catch {
                if request.jsonResponse {
                    return Response(jsonStatus: .conflict)
                }
                return Response(redirect: "./user?emailTaken=true")
            }
        }
        
        // MARK: Logout
        group.get("logout") { request in
            guard let cookie = request.cookies["Server-Auth"] else {
                return Response(redirect: "/user/login")
            }
            let tokenHash = try Application.makeHash(cookie)
            try AccessToken.collection.remove("token" == tokenHash)
            
            let response = Response(redirect: "/user/login")
            response.cookies.insert(User.logoutCookie)
            return response
        }
        
        // MARK: Register
        group.get("register") { request in
            let token = try AuthenticityToken.cookieToken()
            return try drop.view.make("register", [
                "authenticityToken": token,
                "disabled": Admin.settings.registrationEnabled == false,
                "emailTaken": request.data["emailTaken"] != nil,
                "referrer": request.data["referrer"]?.string ?? "none"
            ])
        }
        
        // MARK: Forgot Password
        group.get("forgot-password") { request in
            if let token = request.data["token"]?.string {
                guard let document = try PasswordReset.collection.findOne("token" == token), let userId = document["userId"] as? ObjectId else {
                    throw ServerAbort(.forbidden, reason: "Password reset URL has expired")
                }
                guard let userDocument = try User.collection.findOne("_id" == userId), let email = userDocument["email"] as? String else {
                    throw ServerAbort(.forbidden, reason: "No user account for password reset URL")
                }
                let referrer = document["referrer"] as? String ?? "none"
                return try drop.view.make("forgotPassword", [
                    "passwordResetToken": token,
                    "newPassword": true,
                    "email": email,
                    "failed": request.data["failed"] != nil,
                    "referrer": referrer
                ])
            }
            let token = try AuthenticityToken.cookieToken()
            return try drop.view.make("forgotPassword", [
                "authenticityToken": token,
                "failed": request.data["failed"] != nil,
                "referrer": request.data["referrer"]?.string ?? "none"
            ])
        }
        
        // MARK: Send Forgot Password
        group.post("forgot-password") { request in
            if let token = request.data["passwordResetToken"]?.string {
                let password = try request.data.extract("password") as String
                guard let document = try PasswordReset.collection.findOne("token" == token), let resetId = document.objectId, let userId = document["userId"] as? ObjectId else {
                    throw ServerAbort(.forbidden, reason: "Password reset URL has expired")
                }
                try PasswordReset.collection.remove("_id" == resetId)
                guard let userDocument = try User.collection.findOne("_id" == userId), let email = userDocument["email"] as? String else {
                    throw ServerAbort(.forbidden, reason: "No user account for password reset URL")
                }
                let user = try User.resetPassword(credentials: EmailPassword(email: email, password: password))
                if user.totpRequired {
                    let token = try user.authenticityToken()
                    return try drop.view.make("totp", [
                        "authenticityToken": token,
                        "referrer": request.data["referrer"]?.string ?? "none"
                    ])
                }
                let cookie = try user.cookie(domain: request.uri.domain)
                let referrer = request.data["referrer"]?.string ?? "/admin"
                let response = Response(redirect: (referrer == "none" ? "/admin" : referrer))
                response.cookies.insert(cookie)
                return response
            }
            let email = try request.data.extract("email") as String
            try request.checkAuthenticityToken(oauth: false)
            let referrer = request.data["referrer"]?.string ?? "none"
            do {
                try User.forgotPassword(email: email, referrer: referrer)
            } catch let error {
                Logger.error("Forgot Password Error: \(error)")
            }
            return Response(redirect: "./login?passwordReset=true")
        }
        
        // MARK: Register User
        group.post("register") { request in
            if request.userId == nil {
                guard Admin.settings.registrationEnabled else {
                    return Response(jsonStatus: .notFound)
                }
                try request.checkAuthenticityToken(oauth: false)
            }
            let email = try request.data.extract("email") as String
            let password = try request.data.extract("password") as String
            
            do {
                let user = try User.register(credentials: EmailPassword(email: email, password: password))
                if Admin.settings.domain == nil {
                    Admin.settings.domain = request.uri.domain
                    try Admin.settings.save()
                }
                let cookie = try user.cookie(domain: request.uri.domain)
                let referrer = request.data["referrer"]?.string ?? "/admin"
                let response = Response(redirect: (referrer == "none" ? "/admin" : referrer))
                if referrer != "/user" {
                    response.cookies.insert(cookie)
                }
                return response
            } catch {
                return Response(redirect: "./register?emailTaken=true")
            }
        }
        
        // MARK: Login
        group.get("login") { request in
            let token = try AuthenticityToken.cookieToken()
            
            return try drop.view.make("login", [
                "authenticityToken": token,
                "referrer": request.data["referrer"]?.string ?? "none",
                "passwordReset": request.data["passwordReset"] != nil,
                "unauthorized": request.data["unauthorized"] != nil
            ])
        }
        
        // MARK: Send Login
        group.post("login") { request in
            try request.checkAuthenticityToken(oauth: false)
            let action = try request.data.extract("action") as String
            let credentials: Credentials
            if action == "totp" {
                let code = try request.data.extract("code") as String
                let authenticityToken = try request.data.extract("authenticityToken") as String
                credentials = Totp(code: code, authenticityToken: authenticityToken)
            } else {
                let email = try request.data.extract("email") as String
                let password = try request.data.extract("password") as String
                credentials = EmailPassword(email: email, password: password)
            }
            do {
                let user = try User.login(credentials: credentials)
                if user.totpRequired {
                    let token = try user.authenticityToken()
                    return try drop.view.make("totp", [
                        "authenticityToken": token,
                        "referrer": request.data["referrer"]?.string ?? "none"
                    ])
                }
                if Admin.settings.domain == nil {
                    Admin.settings.domain = request.uri.domain
                    try Admin.settings.save()
                }
                let cookie = try user.cookie(domain: request.uri.domain)
                let referrer = request.data["referrer"]?.string ?? "/admin"
                let response = Response(redirect: (referrer == "none" ? "/admin" : referrer))
                response.cookies.insert(cookie)
                return response
            } catch {
                return Response(redirect: "./login?unauthorized=true")
            }
        }
    }
}
