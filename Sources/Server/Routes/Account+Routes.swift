//
//  Account+Routes.swift
//  Server
//
//  Created by BluDesign, LLC on 8/3/17.
//

import Foundation
import Vapor
import MongoKitten

struct AccountRouter {
    
    init(router: Router) {
        let adminRouter = router.grouped(AdminAuthenticationMiddleware.self)
        
        adminRouter.get(use: get)
        adminRouter.post(use: post)
        adminRouter.post(ObjectId.parameter, use: postAccount)
        adminRouter.get(ObjectId.parameter, use: getAccount)
        adminRouter.post(ObjectId.parameter, "configure", use: postAccountConfigure)
    }
    
    // MARK: GET
    func get(_ request: Request) throws -> Future<ServerResponse> {
        return request.globalAsync { promise in
            let authentication = try request.authentication()
            
            let pageInfo = request.pageInfo
            let documents = try Account.collection.find(sortedBy: ["accountName": .ascending], projecting: [
                "authToken": false
            ], skipping: pageInfo.skip, limitedTo: pageInfo.limit, withBatchSize: pageInfo.limit)
            if request.jsonResponse {
                return promise.submit(try documents.makeResponse(request))
            } else {
                var tableData: String = ""
                for document in documents {
                    guard let accountSid = document["accountSid"], let accountName = document["accountName"], let phoneNumber = document["phoneNumber"], let notificationEmail = document["notificationEmail"], let id = document.objectId else { continue }
                    let string = "<tr onclick=\"location.href='/account/\(id.hexString)'\"><td>\(accountName)</td><td>\(accountSid)</td><td>\(phoneNumber)</td><td>\(notificationEmail)</td></tr>"
                    tableData.append(string)
                }
                let context = TemplateData.dictionary([
                    "tableData": .string(tableData),
                    "admin": .bool(authentication.permission.isAdmin),
                    "contactsEnabled": .bool(Admin.settings.googleClientId != nil && Admin.settings.googleClientSecret != nil)
                ])
                return promise.submit(try request.renderEncoded("accounts", context))
            }
        }
    }
    
    // MARK: POST
    func post(_ request: Request) throws -> Future<ServerResponse> {
        return request.globalAsync { promise in
            struct FormData: Codable {
                let accountName: String
                let notificationEmail: String
                let phoneNumber: String
                let accountSid: String
                let authToken: String
            }
            let formData = try request.content.syncDecode(FormData.self)
            
            let document: Document = [
                "accountName": formData.accountName,
                "notificationEmail": formData.notificationEmail,
                "phoneNumber": formData.phoneNumber,
                "accountSid": formData.accountSid,
                "authToken": formData.authToken
            ]
            guard let objectId = try Account.collection.insert(document) as? ObjectId else {
                throw ServerAbort(.internalServerError, reason: "ObjectID Missing")
            }
            
            return promise.succeed(result: request.serverStatusRedirect(status: .ok, to: "/account/\(objectId.hexString)"))
        }
    }
    
    // MARK: POST :accountId
    func postAccount(_ request: Request) throws -> Future<ServerResponse> {
        return request.globalAsync { promise in
            let objectId = try request.parameters.next(ObjectId.self)
            struct FormData: Codable {
                let action: String?
                let accountName: String?
                let notificationEmail: String?
                let phoneNumber: String?
                let accountSid: String?
                let authToken: String?
            }
            let formData = try request.content.syncDecode(FormData.self)
            
            guard var document = try Account.collection.findOne("_id" == objectId) else {
                throw ServerAbort(.notFound, reason: "Account not found")
            }
            
            if formData.action == "delete" {
                try Account.collection.remove("_id" == objectId)
                return promise.succeed(result: request.serverStatusRedirect(status: .ok, to: "/account"))
            }
            
            if let accountName = formData.accountName {
                document["accountName"] = accountName
            }
            if let notificationEmail = formData.notificationEmail {
                document["notificationEmail"] = notificationEmail
            }
            if let phoneNumber = formData.phoneNumber {
                document["phoneNumber"] = phoneNumber
            }
            if let accountSid = formData.accountSid {
                document["accountSid"] = accountSid
            }
            if let authToken = formData.authToken, authToken.isEmpty == false, authToken != Constants.hiddenText {
                document["authToken"] = authToken
            }
            
            try Account.collection.update("_id" == objectId, to: document, upserting: true)
            
            return promise.succeed(result: request.serverStatusRedirect(status: .ok, to: "/account/\(objectId.hexString)"))
        }
    }
    
    // MARK: GET :accountId
    func getAccount(_ request: Request) throws -> Future<ServerResponse> {
        return request.globalAsync { promise in
            let objectId = try request.parameters.next(ObjectId.self)
            let authentication = try request.authentication()
            
            guard let document = try Account.collection.findOne("_id" == objectId) else {
                throw ServerAbort(.notFound, reason: "Account not found")
            }
            
            if request.jsonResponse {
                return promise.submit(try document.makeResponse(request))
            } else {
                let hasAuthToken = document["authToken"] as? String != nil
                let context = TemplateData.dictionary([
                    "accountName": .string(try document.extract("accountName") as String),
                    "notificationEmail": .string(try document.extract("notificationEmail") as String),
                    "phoneNumber": .string(try document.extract("phoneNumber") as String),
                    "accountSid": .string(try document.extract("accountSid") as String),
                    "accountId": .string(objectId.hexString),
                    "authToken": .string(hasAuthToken ? Constants.hiddenText : ""),
                    "admin": .bool(authentication.permission.isAdmin),
                    "contactsEnabled": .bool(Admin.settings.googleClientId != nil && Admin.settings.googleClientSecret != nil)
                ])
                return promise.submit(try request.renderEncoded("account", context))
            }
        }
    }
    
    // MARK: POST :accountId/configure
    func postAccountConfigure(_ request: Request) throws -> Future<ServerResponse> {
        return request.globalAsync { promise in
            guard let url = Admin.settings.domain else {
                throw ServerAbort(.notFound, reason: "No domain URL set in settings")
            }
            struct Response: Decodable {
                struct PhoneNumber: Decodable {
                    let sid: String
                    let capabilities: Capabilities
                    
                    struct Capabilities: Decodable {
                        let sms: Bool
                    }
                }
                
                let incomingPhoneNumbers: [PhoneNumber]
                
                private enum CodingKeys : String, CodingKey {
                    case incomingPhoneNumbers = "incoming_phone_numbers"
                }
            }
            
            struct Request: Encodable {
                let smsUrl: String
                let smsMethod: String
                
                private enum CodingKeys : String, CodingKey {
                    case smsUrl = "SmsUrl"
                    case smsMethod = "SmsMethod"
                }
            }
            
            let objectId = try request.parameters.next(ObjectId.self)
            
            guard let document = try Account.collection.findOne("_id" == objectId) else {
                throw ServerAbort(.notFound, reason: "Account not found")
            }
            let accountSid = try document.extract("accountSid") as String
            let authToken = try document.extract("authToken") as String
            let accountPhoneNumber = try document.extract("phoneNumber") as String
            
            let requestClient = try request.make(Client.self)
            let headers = HTTPHeaders([
                ("Authorization", "Basic \(try String.twilioAuthString(accountSid, authToken: authToken))"),
                ("Accept", "application/json"),
            ])
            requestClient.get("\(Constants.Twilio.messageUrl)/Accounts/\(accountSid)/IncomingPhoneNumbers.json?PhoneNumber=\(accountPhoneNumber)", headers: headers).do { response in
                guard response.http.status.isValid else {
                    if let error = try? response.content.syncDecode(TwilioError.self) {
                        return promise.fail(error: ServerAbort(response.http.status, reason: "\(error.code): \(error.message)"))
                    }
                    return promise.fail(error: ServerAbort(response.http.status, reason: "Twilio reponse error"))
                }
                do {
                    let response = try response.content.syncDecode(Response.self)
                    guard let phoneNumber = response.incomingPhoneNumbers.first else {
                        throw ServerAbort(.notFound, reason: "Phone number not found")
                    }
                    guard phoneNumber.capabilities.sms else {
                        throw ServerAbort(.notFound, reason: "Phone number does not support SMS")
                    }
                    requestClient.post("\(Constants.Twilio.messageUrl)/Accounts/\(accountSid)/IncomingPhoneNumbers/\(phoneNumber.sid).json", headers: headers, beforeSend: { request in
                        try request.content.encode(Request(smsUrl: "\(url)/message/twiml", smsMethod: "POST"), as: .urlEncodedForm)
                    }).do { response in
                        guard response.http.status.isValid else {
                            if let error = try? response.content.syncDecode(TwilioError.self) {
                                return promise.fail(error: ServerAbort(response.http.status, reason: "\(error.code): \(error.message)"))
                            }
                            return promise.fail(error: ServerAbort(response.http.status, reason: "Twilio reponse error"))
                        }
                        return promise.succeed(result: request.serverStatusRedirect(status: .ok, to: "/account/\(objectId.hexString)"))
                    }.catch { error in
                        return promise.fail(error: error)
                    }
                } catch let error {
                    return promise.fail(error: error)
                }
            }.catch { error in
                return promise.fail(error: error)
            }
        }
    }
}
