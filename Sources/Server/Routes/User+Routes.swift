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
import Leaf

struct UserRouter {
    
    init(router: Router) {
        let protectedRouter = router.grouped(AuthenticationMiddleware.self)
        let adminRouter = router.grouped(AdminAuthenticationMiddleware.self)
        
        router.get("login", use: getLogin)
        router.post("login", use: postLogin)
        router.get("register", use: getRegister)
        router.post("register", use: postRegister)
        router.get("forgot-password", use: getForgotPassword)
        router.post("forgot-password", use: postForgotPassword)
        router.post(ObjectId.parameter, "totp", use: postUserTotp)
        protectedRouter.get(use: get)
        protectedRouter.get(ObjectId.parameter, use: getUser)
        protectedRouter.get("me", use: getUser)
        protectedRouter.post(ObjectId.parameter, use: postUser)
        protectedRouter.post("me", use: postUser)
        protectedRouter.get("logout", use: logout)
        protectedRouter.post("logout", use: logout)
        adminRouter.post(use: post)
    }
    
    // MARK: POST
    func post(_ request: Request) throws -> Future<ServerResponse> {
        return request.globalAsync { promise in
            struct FormData: Codable {
                let email: String
                let password: String
                let permission: User.Permission?
            }
            let formData = try request.content.syncDecode(FormData.self)
            do {
                try User.register(credentials: EmailPassword(email: formData.email, password: formData.password), permission: formData.permission ?? .admin)
                return promise.succeed(result: request.serverStatusRedirect(status: .ok, to: "/user"))
            } catch {
                return promise.succeed(result: request.serverStatusRedirect(status: .conflict, to: "/user?emailTaken=true"))
            }
        }
    }
    
    // MARK: GET :userId
    func getUser(_ request: Request) throws -> Future<ServerResponse> {
        return request.globalAsync { promise in
            let authentication = try request.authentication()
            let userId: ObjectId
            if request.parameters.values.isEmpty {
                userId = authentication.userId
            } else {
                userId = try request.parameters.next(ObjectId.self)
            }
            guard authentication.permission.isAdmin || userId == authentication.userId else {
                return promise.succeed(result: request.serverStatusRedirect(status: .forbidden, to: "/user"))
            }
            guard var document = try User.collection.findOne("_id" == userId, projecting: [
                "password": false,
                "totpToken": false
            ]) else {
                throw ServerAbort(.notFound, reason: "User not found")
            }
            
            if request.jsonResponse {
                document["canDelete"] = (Admin.settings.regularUserCanDelete ? authentication.permission != .readOnly : authentication.permission.isAdmin)
                return promise.submit(try document.makeResponse(request))
            } else {
                let pageInfo = request.pageInfo
                let pushDevices = try PushDevice.collection.find("userId" == userId, sortedBy: ["updatedAt": .ascending], skipping: pageInfo.skip, limitedTo: pageInfo.limit, withBatchSize: pageInfo.limit)
                
                let link = "/user/\(userId.hexString)?"
                var pages = try (pushDevices.count() / pageInfo.limit) + 1
                let startPage: Int
                if pages > 7 {
                    let firstPage = pageInfo.page - 3
                    let lastPage = pageInfo.page + 2
                    startPage = max(pageInfo.page - 3 - (lastPage > pages ? lastPage - pages : 0), 0)
                    pages = min(pages, lastPage - (firstPage < 0 ? firstPage : 0))
                } else {
                    startPage = 0
                }
                var pageData: String = ""
                for x in startPage..<pages {
                    pageData.append("<li class=\"page-item\(x == pageInfo.page - 1 ? " active" : "")\"><a class=\"page-link\" href=\"\(link)page=\(x + 1)\">\(x + 1)</a></li>")
                }
                var tableData: String = ""
                for pushDevice in pushDevices {
                    let deviceName = try pushDevice.extractString("deviceName")
                    let lastActionDate = try pushDevice.extractDate("updatedAt")
                    let deviceToken = try pushDevice.extractString("deviceToken")
                    let string = "<tr><td>\(deviceName)</td><td>\(lastActionDate.longString)</td><td>\(deviceToken)</td></tr>"
                    tableData.append(string)
                }
                
                let email = try document.extract("email") as String
                let userPermission = try document.extractUserPermission("permission")
                let totpActivated = try? document.extract("totpActivated") as Bool
                
                let context = TemplateData.dictionary([
                    "tableData": .string(tableData),
                    "pageData": .string(pageData),
                    "page": .int(pageInfo.page),
                    "nextPage": .string((pageInfo.page + 1 > pages ? "#" : "\(link)page=\(pageInfo.page + 1)")),
                    "prevPage": .string((pageInfo.page - 1 <= 0 ? "#" : "\(link)page=\(pageInfo.page - 1)")),
                    "permission": .int(userPermission.rawValue),
                    "userId": .string(userId.hexString),
                    "email": .string(email),
                    "totpActivated": .bool(totpActivated ?? false),
                    "admin": .bool(authentication.permission.isAdmin),
                    "contactsEnabled": .bool(Admin.settings.googleClientId != nil && Admin.settings.googleClientSecret != nil)
                ])
                return promise.submit(try request.renderEncoded("user", context))
            }
        }
    }
    
    // MARK: GET/POST logout
    func logout(_ request: Request) throws -> Future<ServerResponse> {
        return request.globalAsync { promise in
            func removeAccessToken(_ token: String) throws {
                let tokenHash = try MainApplication.makeHash(token)
                try AccessToken.collection.remove("token" == tokenHash)
            }
            if let authorization = request.http.headers["Authorization"].first?.components(separatedBy: " ").last {
                try removeAccessToken(authorization)
            }
            if let cookie = request.http.cookies["Server-Auth"]?.string {
                try removeAccessToken(cookie)
            }
            if request.jsonResponse {
                let response = request.statusResponse(status: .ok)
                response.http.cookies = User.logoutCookie
                return promise.succeed(result: ServerResponse.response(response))
            } else {
                let response = request.redirect(to: "/user/login")
                response.http.cookies = User.logoutCookie
                return promise.succeed(result: ServerResponse.response(response))
            }
        }
    }
    
    // MARK: POST :userId
    func postUser(_ request: Request) throws -> Future<ServerResponse> {
        return request.globalAsync { promise in
            let authentication = try request.authentication()
            let userId: ObjectId
            if request.parameters.values.isEmpty {
                userId = authentication.userId
            } else {
                userId = try request.parameters.next(ObjectId.self)
            }
            guard authentication.permission.isAdmin || userId == authentication.userId else {
                return promise.succeed(result: request.serverStatusRedirect(status: .forbidden, to: "/user"))
            }
            guard var document = try User.collection.findOne("_id" == userId) else {
                throw ServerAbort(.notFound, reason: "User not found")
            }
            struct FormData: Codable {
                let email: String?
                let password: String?
                let admin: Bool?
                let action: String?
            }
            let formData = try request.content.syncDecode(FormData.self)
            
            if formData.action == "delete" {
                try AccessToken.collection.remove("userId" == userId)
                try PushDevice.collection.remove("userId" == userId)
                try User.collection.remove("_id" == userId)
                return promise.succeed(result: request.serverStatusRedirect(status: .ok, to: "/user"))
            }
            
            if let email = formData.email, email.isValidEmail() {
                document["email"] = email
            }
            if let password = formData.password {
                document["password"] = try BCrypt.hash(password)
            }
            if let admin = formData.admin, authentication.permission.isAdmin, try User.collection.findOne("_id" != userId && "permission" == 2) != nil {
                document["permission"] = (admin ? User.Permission.admin.rawValue : User.Permission.regular.rawValue)
                try AccessToken.collection.update("userId" == userId, to: ["$set": ["permission": admin]], multiple: true)
            }
            
            try User.collection.update("_id" == userId, to: document, upserting: true)
            
            return promise.succeed(result: request.serverStatusRedirect(status: .ok, to: "/user"))
        }
    }
    
    // MARK: GET
    func get(_ request: Request) throws -> Future<ServerResponse> {
        return request.globalAsync { promise in
            let authentication = try request.authentication()
            if authentication.permission.isAdmin == false, request.jsonResponse == false {
                return promise.succeed(result: request.serverStatusRedirect(status: .forbidden, to: "/user/me"))
            }
            let pageInfo = request.pageInfo
            let query: Query? = (authentication.permission.isAdmin ? nil : ("_id" == authentication.userId))
            let documents = try User.collection.find(query, sortedBy: ["email": .ascending], projecting: [
                "password": false,
                "totpToken": false
            ], skipping: pageInfo.skip, limitedTo: pageInfo.limit, withBatchSize: pageInfo.limit)
            if request.jsonResponse {
                return promise.submit(try documents.makeResponse(request))
            } else {
                var tableData: String = ""
                for document in documents {
                    guard let email = document["email"] as? String, let id = document.objectId, let permission = try? document.extractUserPermission("permission") else { continue }
                    let totpActivated = document["totpActivated"] as? Bool ?? false
                    let badge = (totpActivated ? "success" : "danger")
                    let string = "<tr onclick=\"location.href='/user/\(id.hexString)'\"><td>\(email)</td><td><span class=\"badge badge-\(badge)\">\((totpActivated ? "Enabled" : "Disabled"))</span></td><td>\(permission.description)</td></tr>"
                    tableData.append(string)
                }
                let context = TemplateData.dictionary([
                    "tableData": .string(tableData),
                    "emailTaken": .bool((try? request.query.get(Bool.self, at: "emailTaken")) == true),
                    "admin": .bool(authentication.permission.isAdmin),
                    "contactsEnabled": .bool(Admin.settings.googleClientId != nil && Admin.settings.googleClientSecret != nil)
                ])
                return promise.submit(try request.renderEncoded("users", context))
            }
        }
    }
    
    // MARK: POST login
    func postLogin(_ request: Request) throws -> Future<ServerResponse> {
        return request.globalAsync { promise in
            struct FormData: Codable {
                let action: String
                let email: String?
                let password: String?
                let code: String?
                let authenticityToken: String?
                let referrer: String?
                var getReferrer: String {
                    return referrer ?? "none"
                }
                
                func credentials() throws -> Credentials {
                    if action == "totp" {
                        let code = try self.code.unwrapped("code")
                        let authenticityToken = try self.authenticityToken.unwrapped("authenticityToken")
                        return Totp(code: code, authenticityToken: authenticityToken)
                    } else if action == "login" {
                        let email = try self.email.unwrapped("email")
                        let password = try self.password.unwrapped("password")
                        return EmailPassword(email: email, password: password)
                    } else {
                        throw ServerAbort(.badRequest, reason: "action is invalid")
                    }
                }
            }
            let formData = try request.content.syncDecode(FormData.self)
            
            guard let host = try? request.checkCookieAuthenticityToken() else {
                return promise.succeed(result: request.serverRedirect(to: "./login?referrer=\(formData.getReferrer)"))
            }
            let credentials = try formData.credentials()
            let user: User
            do {
                user = try User.login(credentials: credentials)
            } catch {
                return promise.succeed(result: request.serverRedirect(to: "./login?unauthorized=true&referrer=\(formData.getReferrer)"))
            }
            if user.totpRequired {
                let token = try user.authenticityToken(host: request.http.hostUrl?.fullHost)
                return promise.submit(try request.renderEncoded("totp", [
                    "authenticityToken": token,
                    "referrer": formData.getReferrer
                ]))
            }
            if Admin.settings.domain == nil {
                Admin.settings.domain = request.http.hostUrl?.absoluteString
                try Admin.settings.save()
            }
            let cookies = try user.cookie(domain: host)
            let response = request.redirect(to: (formData.getReferrer == "none" ? "/fax" : formData.getReferrer))
            response.http.cookies = cookies
            return promise.succeed(result: ServerResponse.response(response))
        }
    }
    
    // MARK: GET login
    func getLogin(_ request: Request) throws -> Future<ServerResponse> {
        struct Context: Content, Codable {
            var authenticityToken: String?
            var referrer: String?
            let passwordReset: Bool?
            let unauthorized: Bool?
        }
        var context = try request.query.decode(Context.self)
        context.referrer = context.referrer ?? "none"
        context.authenticityToken = try AuthenticityToken.cookieToken(host: request.http.hostUrl?.fullHost)
        return try request.renderEncoded("login", context)
    }
    
    // MARK: GET Register
    func getRegister(_ request: Request) throws -> Future<ServerResponse> {
        let token = try AuthenticityToken.cookieToken(host: request.http.hostUrl?.fullHost)
        let context = TemplateData.dictionary([
            "authenticityToken": .string(token),
            "disabled": .bool(Admin.settings.registrationEnabled == false),
            "emailTaken": .bool((try? request.query.get(Bool.self, at: "emailTaken")) == true),
            "referrer": .string((try? request.query.get(String.self, at: "referrer")) ?? "none")
        ])
        return try request.renderEncoded("register", context)
    }
    
    // MARK: GET register
    func postRegister(_ request: Request) throws -> Future<ServerResponse> {
        return request.globalAsync { promise in
            struct FormData: Codable {
                let email: String
                let password: String
                let authenticityToken: String
                let referrer: String?
                var getReferrer: String {
                    return referrer ?? "none"
                }
                var credentials: Credentials {
                    return EmailPassword(email: email, password: password)
                }
            }
            let formData = try request.content.syncDecode(FormData.self)
            
            guard Admin.settings.registrationEnabled else {
                return promise.succeed(result: request.serverStatusRedirect(status: .forbidden,to: "./register?referrer=\(formData.getReferrer)"))
            }
            guard let host = try? request.checkCookieAuthenticityToken() else {
                return promise.succeed(result: request.serverRedirect(to: "./login?referrer=\(formData.getReferrer)"))
            }
            do {
                let user = try User.register(credentials: formData.credentials)
                if Admin.settings.domain == nil {
                    Admin.settings.domain = request.http.hostUrl?.absoluteString
                    try Admin.settings.save()
                }
                let cookies = try user.cookie(domain: host)
                let response = request.redirect(to: (formData.getReferrer == "none" ? "/fax" : formData.getReferrer))
                response.http.cookies = cookies
                return promise.succeed(result: ServerResponse.response(response))
            } catch {
                return promise.succeed(result: request.serverRedirect(to: "./register?emailTaken=true&referrer=\(formData.getReferrer)"))
            }
        }
    }
    
    // MARK: GET forgotPassword
    func getForgotPassword(_ request: Request) throws -> Future<ServerResponse> {
        return request.globalAsync { promise in
            let authenticityToken = try AuthenticityToken.cookieToken(host: request.http.hostUrl?.fullHost)
            if let token = try? request.query.get(String.self, at: "token") {
                guard let document = try PasswordReset.collection.findOne("token" == token), let userId = document["userId"] as? ObjectId else {
                    throw ServerAbort(.forbidden, reason: "Password reset URL has expired")
                }
                guard let userDocument = try User.collection.findOne("_id" == userId), let email = userDocument["email"] as? String else {
                    throw ServerAbort(.forbidden, reason: "No user account for password reset URL")
                }
                let context = TemplateData.dictionary([
                    "authenticityToken": .string(authenticityToken),
                    "passwordResetToken": .string(token),
                    "newPassword": .bool(true),
                    "email": .string(email),
                    "failed": .bool((try? request.query.get(Bool.self, at: "failed")) == true),
                    "referrer": .string((try? request.query.get(String.self, at: "referrer")) ?? "none")
                ])
                return promise.submit(try request.renderEncoded("forgotPassword", context))
            }
            let context = TemplateData.dictionary([
                "authenticityToken": .string(authenticityToken),
                "failed": .bool((try? request.query.get(Bool.self, at: "failed")) == true),
                "referrer": .string((try? request.query.get(String.self, at: "referrer")) ?? "none")
            ])
            return promise.submit(try request.renderEncoded("forgotPassword", context))
        }
    }
    
    // MARK: POST forgotPassword
    func postForgotPassword(_ request: Request) throws -> Future<ServerResponse> {
        return request.globalAsync { promise in
            struct FormData: Codable {
                let email: String?
                let password: String?
                let passwordResetToken: String?
                let referrer: String?
                var getReferrer: String {
                    return referrer ?? "none"
                }
            }
            let formData = try request.content.syncDecode(FormData.self)
            
            guard let host = try? request.checkCookieAuthenticityToken() else {
                return promise.succeed(result: request.serverRedirect(to: "./forgot-password?referrer=\(formData.getReferrer)"))
            }
            if let token = formData.passwordResetToken {
                let password = try formData.password.unwrapped("password")
                guard let document = try PasswordReset.collection.findOne("token" == token), let resetId = document.objectId, let userId = document["userId"] as? ObjectId else {
                    throw ServerAbort(.forbidden, reason: "Password reset URL has expired")
                }
                try PasswordReset.collection.remove("_id" == resetId)
                guard let userDocument = try User.collection.findOne("_id" == userId), let email = userDocument["email"] as? String else {
                    throw ServerAbort(.forbidden, reason: "No user account for password reset URL")
                }
                let user = try User.resetPassword(credentials: EmailPassword(email: email, password: password))
                if user.totpRequired {
                    let token = try user.authenticityToken(host: request.http.hostUrl?.fullHost)
                    return promise.submit(try request.renderEncoded("totp", [
                        "authenticityToken": token,
                        "referrer": formData.getReferrer
                    ]))
                }
                let cookies = try user.cookie(domain: host)
                let response = request.redirect(to: (formData.getReferrer == "none" ? "/fax" : formData.getReferrer))
                response.http.cookies = cookies
                return promise.succeed(result: ServerResponse.response(response))
            }
            let email = try formData.email.unwrapped("Email")
            return try User.forgotPassword(email: email, referrer: formData.getReferrer, host: host, redirect: "./login?passwordReset=true&referrer=\(formData.getReferrer)", request: request, promise: promise)
        }
    }
    
    // POST :userId/totp
    func postUserTotp(_ request: Request) throws -> Future<ServerResponse> {
        return request.globalAsync { promise in
            let userId = try request.parameters.next(ObjectId.self)
            let authentication = try request.authentication()
            if authentication.permission.isAdmin == false {
                guard userId == authentication.userId else {
                    return promise.succeed(result: request.serverStatusRedirect(status: .forbidden, to: "/user"))
                }
            }
            guard var document = try User.collection.findOne("_id" == userId) else {
                throw ServerAbort(.notFound, reason: "User not found")
            }
            struct FormData: Codable {
                let action: String?
                let password: String?
                let token: String?
                let referrer: String?
                var getReferrer: String {
                    return referrer ?? "none"
                }
            }
            
            let action = try request.content.syncGet(String.self, at: "action")
            if action == "deactivate" {
                document["totpToken"] = nil
                document["totpActivated"] = false
                try User.collection.update("_id" == userId, to: document)
                return promise.succeed(result: request.serverStatusRedirect(status: .ok, to: "/user/\(userId.hexString)"))
            } else if action == "activate" || action == "resetToken" {
                let token = try TOTP.randomToken()
                document["totpToken"] = token
                document["totpActivated"] = false
                try User.collection.update("_id" == userId, to: document)
                if request.jsonResponse {
                    return promise.succeed(result: request.serverStatus(status: .ok))
                } else {
                    let email = try document.extract("email") as String
                    let token = try document.extract("totpToken") as String
                    let context = TemplateData.dictionary([
                        "userId": .string(userId.hexString),
                        "email": .string(email),
                        "verify": .bool(true),
                        "totpToken": .string(token)
                    ])
                    return promise.submit(try request.renderEncoded("user", context))
                }
            } else if action == "verify" {
                let totpToken = try document.extract("totpToken") as String
                let totpCode = try request.content.syncGet(String.self, at: "code")
                let oldKey = try TOTP.generate(key: totpToken, timeInterval: Date().timeIntervalSince1970 - 25)
                let key = try TOTP.generate(key: totpToken)
                guard key == totpCode || oldKey == totpCode else {
                    throw ServerAbort(.badRequest, reason: "Invalid token")
                }
                
                document["totpActivated"] = true
                try User.collection.update("_id" == userId, to: document)
                return promise.succeed(result: request.serverStatusRedirect(status: .ok, to: "/user/\(userId.hexString)"))
            }
            return promise.succeed(result: request.serverStatusRedirect(status: .ok, to: "/user/\(userId.hexString)"))
        }
    }
}
