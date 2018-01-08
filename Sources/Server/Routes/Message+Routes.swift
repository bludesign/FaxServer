//
//  Message+Routes.swift
//  Server
//
//  Created by BluDesign, LLC on 8/25/17.
//

import Foundation
import Vapor
import MongoKitten
import SMTP

private extension Document {
    
    // MARK: - Methods
    
    private func stringValue(_ key: String) -> String {
        return self[key] as? String ?? "Unkown"
    }
    
    mutating func update(withTwilioJson json: JSON) {
        guard let sid = json["sid"]?.string, let accountSid = json["account_sid"]?.string else {
            return
        }
        self["sid"] = sid
        self["accountSid"] = accountSid
        self["status"] = json["status"]?.string ?? self["status"]
        self["messagingServiceId"] = json["messaging_service_sid"]?.string ?? self["messagingServiceId"]
        self["from"] = json["from"]?.string ?? self["from"] ?? self["from"]
        self["to"] = json["to"]?.string ?? self["to"] ?? self["to"]
        self["numMedia"] = json["num_media"]?.int ?? self["numMedia"]
        self["segments"] = json["num_segments"]?.int ?? self["segments"]
        self["price"] = json["price"]?.double ?? self["price"]
        self["priceUnit"] = json["price_unit"]?.string ?? self["priceUnit"]
        self["apiVersion"] = json["api_version"]?.string ?? self["apiVersion"]
    }
    
    func sendAlert(_ drop: Droplet, objectId: ObjectId, to: String?, subject: String) {
        if Admin.settings.messageSendEmail, let to = to {
            sendEmail(drop, objectId: objectId, to: to, subject: subject)
        }
        if Admin.settings.messageSendApns {
            sendPush(objectId: objectId, subject: subject)
        }
        if Admin.settings.messageSendSlack {
            sendSlack(drop, objectId: objectId, subject: subject)
        }
    }
    
    private func sendEmail(_ drop: Droplet, objectId: ObjectId, to: String, subject: String) {
        let data: NodeRepresentable = [
            "title": subject,
            "from": stringValue("from"),
            "to": stringValue("to"),
            "date": (self["dateCreated"] as? Date)?.longString ?? "Unkown",
            "body": stringValue("body")
        ]
        do {
            let content = try drop.view.make("messageEmail", data).data.makeString()
            try Email(from: Admin.settings.mailgunFromEmail, to: to, subject: subject, body: EmailBody(type: .html, content: content)).send()
        } catch let error {
            Logger.error("Error Sending Email: \(error)")
        }
    }
    
    private func sendPush(objectId: ObjectId, subject: String) {
        if let from = self["from"] as? String {
            let mediaCount = self["numMedia"]?.intValue ?? 0
            let body = (self["body"] as? String) ?? (mediaCount > 0 ? "Image" : "")
            PushProvider.sendPush(threadId: objectId.hexString, title: from, body: body)
        }
    }
    
    private func sendSlack(_ drop: Droplet, objectId: ObjectId, subject: String) {
        guard let webHookUrl = Admin.settings.slackWebHookUrl, let from = self["from"] as? String else { return }
        let mediaCount = self["numMedia"]?.intValue ?? 0
        let body = (self["body"] as? String) ?? (mediaCount > 0 ? "Image" : "")
        
        do {
            let json: JSON = [
                "attachments": [
                    [
                        "fallback": JSON.string("\(body)\nFrom: \(from)"),
                        "title": JSON.string(body),
                        "footer": JSON.string(from),
                        "ts": JSON.number(.double((self["dateCreated"] as? Date ?? Date()).timeIntervalSince1970))
                    ]
                ]
            ]
            _ = try drop.client.post(webHookUrl, [
                "Content-Type": "application/json"
            ], json)
        } catch let error {
            Logger.error("Error Sending Slack: \(error)")
        }
    }
}

extension Message {
    
    // MARK: - Methods
    
    static func routes(_ drop: Droplet, _ group: RouteBuilder) {
        let protected = group.grouped([AuthenticationMiddleware.shared])
        
        // MARK: Send Message
        protected.post { request in
            let jsonResponse = request.jsonResponse
            let userId = try request.getUserId()
            let toString = try request.data.extract("to") as String
            let accountId = try request.data.extract("accountId") as ObjectId
            guard let account = try Account.collection.findOne("_id" == accountId) else {
                throw ServerAbort(.notFound, reason: "Account not found")
            }
            let accountSid = try account.extract("accountSid") as String
            let authToken = try account.extract("authToken") as String
            let phoneNumber = try account.extract("phoneNumber") as String
            let body = try request.data.extract("body") as String
            
            let fromString = request.data["from"]?.string ?? phoneNumber
            
            let token = try String.token()
            var document: Document = [
                "from": fromString,
                "to": toString,
                "userId": userId,
                "body": body,
                "token": token,
                "accountSid": accountSid,
                "direction": "outbound",
                "status": "started",
                "dateCreated": Date(),
                "userId": userId,
                "accountId": accountId
            ]
            guard let objectId = try Message.collection.insert(document) as? ObjectId else {
                throw ServerAbort(.notFound, reason: "Error creating message")
            }
            guard let url = Admin.settings.domain else {
                throw ServerAbort(.notFound, reason: "No host URL set in settings")
            }
            
            let mediaUrl: String?
            if let bytes = request.data["file"]?.bytes, bytes.count > 0 {
                let mimeType: String
                switch bytes[0] {
                case 0xFF: mimeType = "image/jpeg"
                case 0x89: mimeType = "image/png"
                case 0x47: mimeType = "image/gif"
                default:
                    throw ServerAbort(.notFound, reason: "Invalid image format")
                }
                let fileDocument: Document = [
                    "messageObjectId": objectId,
                    "token": token,
                    "dateCreated": Date(),
                    "mimeType": mimeType,
                    "data": Data(bytes: bytes)
                ]
                guard let fileObjectId = try MessageFile.collection.insert(fileDocument) as? ObjectId else {
                    throw ServerAbort(.notFound, reason: "Error creating message file")
                }
                mediaUrl = "\(url)/message/file/\(fileObjectId.hexString)/\(token)"
            } else {
                mediaUrl = nil
            }
            
            let request = Request(method: .post, uri: "\(Constants.Twilio.messageUrl)/Accounts/\(accountSid)/Messages.json", headers: [
                "Authorization": "Basic \(try String.twilioAuthString(accountSid, authToken: authToken))",
                "Content-Type": "application/x-www-form-urlencoded",
                "Accept": "application/json"
            ])
            if let mediaUrl = mediaUrl {
                request.body = .data(try Node(node: [
                    "From": fromString,
                    "To": toString,
                    "MediaUrl": mediaUrl,
                    "StatusCallback": "\(url)/message/status/\(objectId.hexString)/\(token)",
                    "Body": body
                ]).formURLEncodedPlus())
                document["numMedia"] = 1
            } else {
                request.body = .data(try Node(node: [
                    "From": fromString,
                    "To": toString,
                    "StatusCallback": "\(url)/message/status/\(objectId.hexString)/\(token)",
                    "Body": body
                ]).formURLEncodedPlus())
                document["numMedia"] = 0
            }
            
            let response: Response = try drop.client.respond(to: request)
            
            guard response.status.isValid else {
                document["status"] = "failed"
                try Message.collection.update("_id" == objectId, to: document)
                throw ServerAbort(response.status, reason: "Twilio reponse error")
            }
            guard let responseBytes = response.body.bytes else {
                throw ServerAbort(.notFound, reason: "Error parsing response body")
            }
            let json = try JSON(bytes: responseBytes)
            document.update(withTwilioJson: json)
            
            try Message.collection.update("_id" == objectId, to: document)
            
            if jsonResponse {
                guard let document = try Message.collection.findOne("_id" == objectId) else {
                    throw ServerAbort(.notFound, reason: "Message missing")
                }
                return try document.makeResponse()
            } else {
                return Response(redirect: "/message")
            }
        }
        
        // MARK: Update Message Status
        group.post("status", ":objectId") { request in
            let objectId = try request.parameters.extract("objectId") as ObjectId
            let token = request.data["token"]?.string
            return try updateStatus(objectId: objectId, token: token, request: request)
        }
        
        // MARK: Update Message Status
        group.post("status", ":objectId", ":token") { request in
            let objectId = try request.parameters.extract("objectId") as ObjectId
            let token = try request.parameters.extract("token") as String
            return try updateStatus(objectId: objectId, token: token, request: request)
        }
        
        func updateStatus(objectId: ObjectId, token: String? = nil, request: Request) throws -> Response {
            let sid = try request.data.extract("MessageSid") as String
            let accountSid = try request.data.extract("AccountSid") as String
            
            guard var document = try Message.collection.findOne("_id" == objectId) else {
                throw ServerAbort(.notFound, reason: "Message not found")
            }
            
            if request.userId == nil {
                let documentToken = try document.extract("token") as String
                guard token == documentToken else {
                    throw ServerAbort(.notFound, reason: "Invalid message token")
                }
            }
            
            document["sid"] = sid
            document["accountSid"] = accountSid
            document["status"] = request.data["MessageStatus"]?.string
            document["errorCode"] = request.data["ErrorCode"]?.string ?? document["errorCode"]
            document["errorMessage"] = request.data["ErrorMessage"]?.string ?? document["errorMessage"]
            document["messagingServiceId"] = request.data["MessagingServiceSid"]?.string ?? document["messagingServiceId"]
            
            try Message.collection.update("_id" == document.objectId, to: document)
            
            return Response(jsonStatus: .ok)
        }
        
        // MARK: Get Message File
        group.get("file", ":objectId") { request in
            let objectId = try request.parameters.extract("objectId") as ObjectId
            let token = request.data["token"]?.string
            return try getFile(objectId: objectId, token: token, request: request)
        }
        
        // MARK: Get Message File
        group.get("file", ":objectId", ":token") { request in
            let objectId = try request.parameters.extract("objectId") as ObjectId
            let token = try request.parameters.extract("token") as String
            return try getFile(objectId: objectId, token: token, request: request)
        }
        
        func getFile(objectId: ObjectId, token: String? = nil, request: Request) throws -> Response {
            guard let document = try MessageFile.collection.findOne("_id" == objectId) else {
                throw ServerAbort(.notFound, reason: "Message not found")
            }
            
            if request.userId == nil {
                guard let documentToken = document["token"] as? String, token == documentToken else {
                    return Response(redirect: "/user/login?referrer=/message/file/\(objectId.hexString)")
                }
            }
            
            let mimeType = try document.extract("mimeType") as String
            guard let bytes = Data(document["data"])?.makeBytes() else {
                throw ServerAbort(.notFound, reason: "Message file empty")
            }
            
            return Response(status: .ok, headers: ["Content-Type": mimeType], body: .data(bytes))
        }
        
        // MARK: Nexmo
        group.get("nexmo") { request in
            guard Admin.settings.nexmoEnabled else {
                throw ServerAbort(.notFound, reason: "Nexmo is disabled")
            }
            let sid = try request.data.extract("messageId") as String
            let document: Document = [
                "sid": sid,
                "from": request.data["msisdn"]?.string,
                "to": request.data["to"]?.string,
                "body": request.data["text"]?.string,
                "direction": "inbound",
                "status": "received",
                "dateCreated": Date()
            ]
            
            guard let objectId = try Message.collection.insert(document) as? ObjectId else {
                throw ServerAbort(.notFound, reason: "Error creating message")
            }
            
            document.sendAlert(drop, objectId: objectId, to: Admin.settings.notificationEmail, subject: "Message Received")
            
            return Response(status: .ok)
        }
        
        // MARK: Twiml
        group.post("twiml") { request in
            return try twiml(request: request)
        }
        group.get("twiml") { request in
            return try twiml(request: request)
        }
        
        func twiml(request: Request) throws -> Response {
            let sid = try request.data.extract("MessageSid") as String
            let accountSid = try request.data.extract("AccountSid") as String
            guard let account = try Account.collection.findOne("accountSid" == accountSid) else {
                throw ServerAbort(.notFound, reason: "Account not found")
            }
            
            var document: Document = [
                "sid": sid,
                "accountSid": accountSid,
                "from": request.data["From"]?.string,
                "to": request.data["To"]?.string,
                "messagingServiceId": request.data["MessagingServiceSid"]?.string,
                "body": request.data["Body"]?.string,
                "numMedia": request.data["NumMedia"]?.int,
                "errorCode": request.data["ErrorCode"]?.string,
                "errorMessage": request.data["ErrorMessage"]?.string,
                "direction": "inbound",
                "status": "received",
                "dateCreated": Date()
            ]
            
            document["fromCity"] = request.data["FromCity"]?.string
            document["fromState"] = request.data["FromState"]?.string
            document["fromZip"] = request.data["FromZip"]?.string
            document["fromCountry"] = request.data["FromCountry"]?.string
            document["toCity"] = request.data["ToCity"]?.string
            document["toState"] = request.data["ToState"]?.string
            document["toZip"] = request.data["ToZip"]?.string
            document["toCountry"] = request.data["ToCountry"]?.string
            
            guard let objectId = try Message.collection.insert(document) as? ObjectId else {
                throw ServerAbort(.notFound, reason: "Error creating message")
            }
            if let mediaCount = request.data["NumMedia"]?.int {
                for x in 0 ..< mediaCount {
                    guard let mediaUrl = request.data["MediaUrl\(x)"]?.string, let contentType = request.data["MediaContentType\(x)"]?.string else {
                        Logger.error("Load Message Media: No media URL or content type")
                        continue
                    }
                    var response = try EngineClient.factory.get(mediaUrl)
                    var count = 0
                    while response.status != .ok, let location = response.headers["Location"]?.string {
                        guard count < 5 else {
                            break
                        }
                        response = try EngineClient.factory.get(location)
                        count += 1
                    }
                    guard response.status == .ok else {
                        Logger.error("Load Message Media: Invalid response")
                        continue
                    }
                    guard let bytes = response.body.bytes else {
                        Logger.error("Load Message Media: No response body")
                        continue
                    }
                    let fileToken = try String.token()
                    let fileDocument: Document = [
                        "messageObjectId": objectId,
                        "token": fileToken,
                        "dateCreated": Date(),
                        "mimeType": contentType,
                        "mediaNumber": x,
                        "data": Data(bytes: bytes)
                    ]
                    try MessageFile.collection.insert(fileDocument)
                }
            }
            
            document.sendAlert(drop, objectId: objectId, to: account["notificationEmail"] as? String ?? Admin.settings.notificationEmail, subject: "Message Received")
            
            let responseString = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><Response></Response>"
            return Response(
                status: .ok,
                headers: ["Content-Type": "text/xml"],
                body: responseString.makeBytes()
            )
        }
        
        // MARK: Get Messages
        protected.get { request in
            let phoneNumber = try? request.data.extract("phoneNumber") as String
            let pageInfo = request.pageInfo
            let filter: Query?
            let link: String
            if let phoneNumber = phoneNumber {
                link = "/message?phoneNumber=\(phoneNumber.urlQueryPercentEncodedPlus)&"
                let query: Query = "from" == phoneNumber || "to" == phoneNumber
                filter = query
            } else {
                link = "/message?"
                filter = nil
            }
            let documents = try Message.collection.find(filter, sortedBy: ["dateCreated": .descending], projecting: [
                "sid": false,
                "accountSid": false,
                "messagingServiceId": false
            ], skipping: pageInfo.skip, limitedTo: pageInfo.limit, withBatchSize: pageInfo.limit)
            if request.jsonResponse {
                return try documents.makeResponse()
            } else {
                var pages = try (documents.count() / pageInfo.limit) + 1
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
                
                let accountDocuments = try Account.collection.find(sortedBy: ["accountName": .ascending], projecting: [
                    "authToken": false,
                    "accountSid": false
                ], skipping: 0, limitedTo: 100, withBatchSize: 100)
                
                var accountData: String = ""
                for document in accountDocuments {
                    guard let accountName = document["accountName"], let id = document.objectId else {
                        continue
                    }
                    let string = "<option value=\"\(id.hexString)\">\(accountName)</option>"
                    accountData.append(string)
                }
                if accountData.isEmpty {
                    accountData = "<option value=\"none\">No Accounts</option>"
                }
                
                var tableData: String = ""
                for document in documents {
                    guard let from = document["from"], let to = document["to"], let dateCreated = document["dateCreated"] as? Date, let id = document.objectId else {
                        continue
                    }
                    let body = document["body"] as? String ?? ""
                    let status = (document["status"] as? String)?.statusString ?? ""
                    let badge: String
                    if status == "Received" || status == "Delivered" {
                        badge = "success"
                    } else if status == "Failed" {
                        badge = "danger"
                    } else {
                        badge = "default"
                    }
                    let mediaCount = document["numMedia"]?.numberString ?? ""
                    let string = "<tr onclick=\"location.href='/message/\(id.hexString)'\"><td>\(from)</td><td>\(to)</td><td>\(dateCreated.longString)</td><td>\(body)</td><td>\(mediaCount)</td><td><span class=\"badge badge-\(badge)\">\(status)</span></td></tr>"
                    tableData.append(string)
                }
                return try drop.view.make("messages", [
                    "tableData": tableData,
                    "accountData": accountData,
                    "pageData": pageData,
                    "page": pageInfo.page,
                    "phoneNumber": phoneNumber ?? "",
                    "nextPage": (pageInfo.page + 1 > pages.count ? "#" : "/\(link)page=\(pageInfo.page + 1)"),
                    "prevPage": (pageInfo.page - 1 <= 0 ? "#" : "\(link)page=\(pageInfo.page - 1)")
                ])
            }
        }
        
        // MARK: Get Message
        protected.get(":objectId") { request in
            let objectId = try request.parameters.extract("objectId") as ObjectId
            
            guard let document = try Message.collection.findOne("_id" == objectId, projecting: [
                "sid": false,
                "accountSid": false,
                "messagingServiceId": false
            ]) else {
                throw ServerAbort(.notFound, reason: "Message not found")
            }
            
            if request.jsonResponse {
                return try document.makeResponse()
            } else {
                let from = document["from"] as? String ?? "Unkown"
                let to = document["to"] as? String ?? "Unkown"
                let dateCreated = (document["dateCreated"] as? Date)?.longString ?? "Unkown"
                let body = document["body"] as? String ?? ""
                let mediaCount = document["numMedia"]?.numberString ?? ""
                let status = (document["status"] as? String)?.statusString ?? ""
                let badge: String
                if status == "Received" || status == "Delivered" {
                    badge = "success"
                } else if status == "Failed" {
                    badge = "danger"
                } else {
                    badge = "warning"
                }
                
                let toLocation: String
                if let city = document["toCity"] as? String, let state = document["toState"] as? String, let country = document["toCountry"] as? String {
                    toLocation = "\(city), \(state), \(country)"
                } else {
                    toLocation = "Unkown"
                }
                let fromLocation: String
                if let city = document["fromCity"] as? String, let state = document["fromState"] as? String, let country = document["fromCountry"] as? String {
                    fromLocation = "\(city), \(state), \(country)"
                } else {
                    fromLocation = "Unkown"
                }
                
                var mediaFiles = ""
                if document["numMedia"]?.intValue ?? 0 > 0 {
                    guard let url = Admin.settings.domain else {
                        throw ServerAbort(.notFound, reason: "No host URL set in settings")
                    }
                    let mediaDocuments = try MessageFile.collection.find("messageObjectId" == objectId, projecting: [
                        "data": false
                    ])
                    for mediaDocument in mediaDocuments {
                        guard let objectId = mediaDocument.objectId?.hexString else { continue }
                        mediaFiles.append("\n<tr><td>Media \(1)</td><td><a href=\"\(url)/message/file/\(objectId)\"><img src=\"\(url)/message/file/\(objectId)\" class=\"rounded\" style=\"max-width: 400px;\"></a></td></tr>")
                    }
                }
                
                return try drop.view.make("message", [
                    "from": from,
                    "to": to,
                    "fromLocation": fromLocation,
                    "toLocation": toLocation,
                    "date": dateCreated,
                    "status": "<span class=\"badge badge-\(badge)\">\(status)</span>",
                    "mediaCount": mediaCount,
                    "body": body,
                    "mediaFiles": mediaFiles
                ])
            }
        }
    }
}
