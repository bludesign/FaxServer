//
//  Account+Routes.swift
//  Server
//
//  Created by BluDesign, LLC on 8/3/17.
//

import Foundation
import Vapor
import MongoKitten

extension Account {
    
    // MARK: - Methods
    
    static func routes(_ drop: Droplet, _ group: RouteBuilder, authenticationMiddleware: AuthenticationMiddleware) {
        let protected = group.grouped([authenticationMiddleware])
        
        // MARK: Get Accounts
        protected.get { request in
            let skip = request.data["skip"]?.int ?? 0
            let limit = min(100, request.data["limit"]?.int ?? 100)
            let documents = try Account.collection.find(sortedBy: ["accountName": .ascending], projecting: [
                "authToken": false
            ], skipping: skip, limitedTo: limit, withBatchSize: limit)
            if request.jsonResponse {
                return try documents.makeResponse()
            } else {
                var tableData: String = ""
                for document in documents {
                    guard let accountSid = document["accountSid"], let accountName = document["accountName"], let phoneNumber = document["phoneNumber"], let notificationEmail = document["notificationEmail"], let id = document.objectId else {
                        continue
                    }
                    let string = "<tr onclick=\"location.href='/account/\(id.hexString)'\"><td>\(accountName)</td><td>\(accountSid)</td><td>\(phoneNumber)</td><td>\(notificationEmail)</td></tr>"
                    tableData.append(string)
                }
                return try drop.view.make("accounts", ["tableData": tableData])
            }
        }
        
        // MARK: Create Account
        protected.post { request in
            let accountName = try request.data.extract("accountName") as String
            let notificationEmail = try request.data.extract("notificationEmail") as String
            let phoneNumber = try request.data.extract("phoneNumber") as String
            let accountSid = try request.data.extract("accountSid") as String
            let authToken = try request.data.extract("authToken") as String
            
            let document: Document = [
                "accountName": accountName,
                "notificationEmail": notificationEmail,
                "phoneNumber": phoneNumber,
                "accountSid": accountSid,
                "authToken": authToken
            ]
            try Account.collection.insert(document)
            
            if request.jsonResponse {
                return Response(jsonStatus: .ok)
            }
            return Response(redirect: "/account")
        }
        
        // MARK: Update Account
        protected.post(":objectId") { request in
            let objectId = try request.parameters.extract("objectId") as ObjectId
            
            guard var document = try Account.collection.findOne("_id" == objectId) else {
                throw ServerAbort(.notFound, reason: "Account not found")
            }
            
            if request.data["action"]?.string == "delete" {
                try Account.collection.remove("_id" == objectId)
                if request.jsonResponse {
                    return Response(jsonStatus: .ok)
                }
                return Response(redirect: "/account")
            }
            
            if let accountName = try? request.data.extract("accountName") as String {
                document["accountName"] = accountName
            }
            if let notificationEmail = try? request.data.extract("notificationEmail") as String {
                document["notificationEmail"] = notificationEmail
            }
            if let phoneNumber = try? request.data.extract("phoneNumber") as String {
                document["phoneNumber"] = phoneNumber
            }
            if let accountSid = try? request.data.extract("accountSid") as String {
                document["accountSid"] = accountSid
            }
            if let authToken = try? request.data.extract("authToken") as String {
                document["authToken"] = authToken
            }
            
            try Account.collection.update("_id" == objectId, to: document, upserting: true)
            
            if request.jsonResponse {
                return Response(jsonStatus: .ok)
            }
            return Response(redirect: "/account")
        }
        
        // MARK: Get Account
        protected.get(":objectId") { request in
            let objectId = try request.parameters.extract("objectId") as ObjectId
            
            guard let document = try Account.collection.findOne("_id" == objectId) else {
                throw ServerAbort(.notFound, reason: "Account not found")
            }
            
            if request.jsonResponse {
                return try document.makeResponse()
            } else {
                return try drop.view.make("account", [
                    "accountName": try document.extract("accountName") as String,
                    "notificationEmail": try document.extract("notificationEmail") as String,
                    "phoneNumber": try document.extract("phoneNumber") as String,
                    "accountSid": try document.extract("accountSid") as String,
                    "accountId": objectId.hexString
                ])
            }
        }
        
        // MARK: Configure Account
        protected.post(":objectId", "configure") { request in
            let objectId = try request.parameters.extract("objectId") as ObjectId
            
            guard let document = try Account.collection.findOne("_id" == objectId) else {
                throw ServerAbort(.notFound, reason: "Account not found")
            }
            let accountSid = try document.extract("accountSid") as String
            let authToken = try document.extract("authToken") as String
            let accountPhoneNumber = try document.extract("phoneNumber") as String
            let twilioRequest = Request(method: .get, uri: "\(Constants.Twilio.messageUrl)/Accounts/\(accountSid)/IncomingPhoneNumbers.json?PhoneNumber=\(accountPhoneNumber)", headers: [
                "Authorization": "Basic \(try String.twilioAuthString(accountSid, authToken: authToken))",
                "Content-Type": "application/x-www-form-urlencoded",
                "Accept": "application/json"
            ])
            
            let response: Response = try drop.client.respond(to: twilioRequest)
            guard response.status.isValid else {
                throw ServerAbort(response.status, reason: "Twilio reponse error")
            }
            guard let responseBytes = response.body.bytes else {
                throw ServerAbort(.notFound, reason: "Error parsing response body")
            }
            let json = try JSON(bytes: responseBytes)
            
            guard let phoneNumbers = json["incoming_phone_numbers"]?.array else {
                throw ServerAbort(.notFound, reason: "Error parsing response phone numbers")
            }
            guard let phoneNumber = phoneNumbers.first, let phoneNumberSid = phoneNumber["sid"]?.string else {
                throw ServerAbort(.notFound, reason: "Phone number not found on Twilio account")
            }
            guard let capabilities = phoneNumber["capabilities"]?.makeJSON(), capabilities["sms"]?.bool == true else {
                throw ServerAbort(.notFound, reason: "Phone number does not support sms")
            }
            
            let updateRequest = Request(method: .post, uri: "\(Constants.Twilio.messageUrl)/Accounts/\(accountSid)/IncomingPhoneNumbers/\(phoneNumberSid).json", headers: [
                "Authorization": "Basic \(try String.twilioAuthString(accountSid, authToken: authToken))",
                "Content-Type": "application/x-www-form-urlencoded",
                "Accept": "application/json"
            ])
            guard let url = Admin.settings.domain else {
                throw ServerAbort(.notFound, reason: "No host URL set in settings")
            }
            updateRequest.body = .data(try Node(node: [
                "SmsUrl": "\(url)/message/twiml",
                "SmsMethod": "POST"
            ]).formURLEncodedPlus())
            
            let updateResponse: Response = try drop.client.respond(to: updateRequest)
            guard updateResponse.status.isValid else {
                throw ServerAbort(response.status, reason: "Twilio reponse error")
            }
            
            if request.jsonResponse {
                return Response(jsonStatus: .ok)
            } else {
                return Response(redirect: "/account/\(objectId.hexString)")
            }
        }
    }
}
