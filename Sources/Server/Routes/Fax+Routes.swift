//
//  Fax+Routes.swift
//  Server
//
//  Created by BluDesign, LLC on 6/29/17.
//

import Foundation
import Vapor
import MongoKitten
import SMTP

private enum AlertType {
    case faxReceived, faxStatus
}

private extension Document {
    
    // MARK: - Methods
    
    private func stringValue(_ key: String) -> String {
        return self[key] as? String ?? "Unkown"
    }
    
    mutating func update(withTwilioJson json: JSON) {
        guard let sid = json["sid"]?.string, let accountSid = json["account_sid"]?.string else {
            return
        }
        self["mediaSid"] = json["media_sid"]?.string ?? self["mediaSid"]
        self["status"] = json["status"]?.string ?? self["status"]
        self["direction"] = json["direction"]?.string ?? self["direction"]
        self["from"] = json["from"]?.string ?? self["from"] ?? self["from"]
        self["to"] = json["to"]?.string ?? self["to"] ?? self["to"]
        self["dateUpdated"] = json["date_updated"]?.iso8601Date ?? self["dateUpdated"]
        self["price"] = json["price"]?.double ?? self["price"]
        self["accountSid"] = accountSid
        self["dateCreated"] = json["date_created"]?.iso8601Date ?? self["dateCreated"]
        self["url"] = json["url"]?.string ?? self["url"]
        self["sid"] = sid
        self["duration"] = json["duration"]?.int ?? self["duration"]
        self["pages"] = json["num_pages"]?.int ?? self["pages"]
        self["quality"] = json["quality"]?.string ?? self["quality"]
        self["priceUnit"] = json["price_unit"]?.string ?? self["priceUnit"]
        self["apiVersion"] = json["api_version"]?.string ?? self["apiVersion"]
        self["mediaUrl"] = json["media_url"]?.string ?? self["mediaUrl"]
    }
    
    func sendAlert(_ drop: Droplet, objectId: ObjectId, to: String?, subject: String, alertType: AlertType) {
        if (alertType == .faxStatus ? Admin.settings.faxStatusSendEmail : Admin.settings.faxReceivedSendEmail), let to = to {
            sendEmail(drop, objectId: objectId, to: to, subject: subject)
        }
        if (alertType == .faxStatus ? Admin.settings.faxStatusSendApns : Admin.settings.faxReceivedSendApns) {
            sendPush(objectId: objectId, subject: subject)
        }
        if (alertType == .faxStatus ? Admin.settings.faxStatusSendSlack : Admin.settings.faxReceivedSendSlack) {
            sendSlack(drop, objectId: objectId, subject: subject)
        }
    }
    
    private func sendEmail(_ drop: Droplet, objectId: ObjectId, to: String, subject: String) {
        guard let url = Admin.settings.domain else {
            Logger.error("Error Sending Email: No host URL set in settings")
            return
        }
        let data: NodeRepresentable = [
            "title": subject,
            "status": stringValue("status").capitalized,
            "from": stringValue("from"),
            "to": stringValue("to"),
            "date": (self["dateCreated"] as? Date)?.longString ?? "Unkown",
            "direction": stringValue("direction").capitalized,
            "quality": stringValue("quality").capitalized,
            "pages": self["pages"]?.numberString ?? "",
            "duration": self["duration"]?.intValue?.timeString ?? "",
            "mediaUrl": "\(url)/fax/file/\(objectId.hexString)"
        ]
        do {
            let content = try drop.view.make("faxStatusEmail", data).data.makeString()
            try Email(from: Admin.settings.mailgunFromEmail, to: to, subject: subject, body: EmailBody(type: .html, content: content)).send()
        } catch let error {
            Logger.error("Error Sending Email: \(error)")
        }
    }
    
    private func sendPush(objectId: ObjectId, subject: String) {
        if let from = self["from"] as? String, let to = self["to"] as? String, let status = (self["status"] as? String)?.capitalized {
            PushProvider.sendPush(threadId: objectId.hexString, title: subject, body: "Status: \(status) From: \(from) To: \(to)")
        }
    }
    
    private func sendSlack(_ drop: Droplet, objectId: ObjectId, subject: String) {
        guard let webHookUrl = Admin.settings.slackWebHookUrl, let from = self["from"] as? String, let to = self["to"] as? String, let status = (self["status"] as? String)?.capitalized else { return }
        guard let url = Admin.settings.domain else {
            Logger.error("Error Sending Email: No host URL set in settings")
            return
        }
        let mediaUrl = "\(url)/fax/file/\(objectId.hexString)"
        
        do {
            let json: JSON = [
                "attachments": [
                    [
                        "fallback": JSON.string("<\(mediaUrl)|\(subject)> Status: \(status) From: \(from) To: \(to)"),
                        "title": JSON.string("\(subject)"),
                        "title_link": JSON.string(mediaUrl),
                        "fields": [
                            [
                                "title": "Status",
                                "value": JSON.string(subject),
                                "short": false
                            ], [
                                "title": "From",
                                "value": JSON.string(from),
                                "short": false
                            ], [
                                "title": "To",
                                "value": JSON.string(to),
                                "short": false
                            ]
                        ],
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

extension Fax {
    
    // MARK: - Methods
    
    static func routes(_ drop: Droplet, _ group: RouteBuilder) {
        let protected = group.grouped([AuthenticationMiddleware.shared])
        
        // MARK: Twiml
        group.post("twiml") { _ in
            return try twiml()
        }
        group.get("twiml") { _ in
            return try twiml()
        }
        
        func twiml() throws -> Response {
            guard let url = Admin.settings.domain else {
                throw ServerAbort(.notFound, reason: "No host URL set in settings")
            }
            let responseString = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><Response><Receive action=\"\(url)/fax/receive\"/></Response>"
            return Response(
                status: .ok,
                headers: ["Content-Type": "text/xml"],
                body: responseString.makeBytes()
            )
        }
        
        // MARK: Send Fax
        protected.post { request in
            let jsonResponse = request.jsonResponse
            let userId = try request.getUserId()
            let toString = try request.data.extract("to") as String
            let senderEmail = try request.data.extractValidatedEmail("senderEmail") as String
            let accountId = try request.data.extract("accountId") as ObjectId
            guard let account = try Account.collection.findOne("_id" == accountId) else {
                throw ServerAbort(.notFound, reason: "Account not found")
            }
            let accountSid = try account.extract("accountSid") as String
            let authToken = try account.extract("authToken") as String
            let phoneNumber = try account.extract("phoneNumber") as String
            guard let bytes = request.data["file"]?.bytes, bytes.count > 0 else {
                throw ServerAbort(.notFound, reason: "file is required")
            }
            guard bytes[0] == 0x25 else {
                throw ServerAbort(.notFound, reason: "Invalid PDF format")
            }
            
            let token = try String.token()
            let fileToken = try String.token()
            let fromString = request.data["from"]?.string ?? phoneNumber
            
            var document: Document = [
                "from": fromString,
                "to": toString,
                "userId": userId,
                "token": token,
                "accountSid": accountSid,
                "senderEmail": senderEmail,
                "status": "started",
                "dateCreated": Date(),
                "accountId": accountId
            ]
            guard let objectId = try Fax.collection.insert(document) as? ObjectId else {
                throw ServerAbort(.notFound, reason: "Error creating fax")
            }
            
            let fileDocument: Document = [
                "faxObjectId": objectId,
                "token": fileToken,
                "dateCreated": Date(),
                "data": Data(bytes: bytes)
            ]
            try FaxFile.collection.insert(fileDocument)
            
            let request = Request(method: .post, uri: "\(Constants.Twilio.faxUrl)/Faxes", headers: [
                "Authorization": "Basic \(try String.twilioAuthString(accountSid, authToken: authToken))",
                "Content-Type": "application/x-www-form-urlencoded",
                "Accept": "application/json"
            ])
            guard let url = Admin.settings.domain else {
                throw ServerAbort(.notFound, reason: "No host URL set in settings")
            }
            request.body = .data(try Node(node: [
                "From": fromString,
                "To": toString,
                "MediaUrl": "\(url)/fax/file/\(objectId.hexString)/\(fileToken)",
                "StatusCallback": "\(url)/fax/status/\(objectId.hexString)/\(token)"
            ]).formURLEncodedPlus())
            
            let response: Response = try drop.client.respond(to: request)
            
            guard response.status.isValid else {
                document["status"] = "failed"
                try Fax.collection.update("_id" == objectId, to: document)
                throw ServerAbort(response.status, reason: "Twilio reponse error")
            }
            guard let responseBytes = response.body.bytes else {
                throw ServerAbort(.notFound, reason: "Error parsing response body")
            }
            let json = try JSON(bytes: responseBytes)
            document.update(withTwilioJson: json)
            
            try Fax.collection.update("_id" == objectId, to: document)
            
            document.sendAlert(drop, objectId: objectId, to: senderEmail, subject: "Fax Sent", alertType: .faxStatus)
            
            if jsonResponse {
                guard let document = try Fax.collection.findOne("_id" == objectId) else {
                    throw ServerAbort(.notFound, reason: "Fax missing")
                }
                return try document.makeResponse()
            } else {
                return Response(redirect: "/fax")
            }
        }
        
        // MARK: Update Fax Status
        group.post("status", ":objectId") { request in
            let objectId = try request.parameters.extract("objectId") as ObjectId
            let token = request.data["token"]?.string
            return try updateStatus(objectId: objectId, token: token, request: request)
        }
        
        // MARK: Update Fax Status
        group.post("status", ":objectId", ":token") { request in
            let objectId = try request.parameters.extract("objectId") as ObjectId
            let token = try request.parameters.extract("token") as String
            return try updateStatus(objectId: objectId, token: token, request: request)
        }
        
        func updateStatus(objectId: ObjectId, token: String? = nil, request: Request) throws -> Response {
            let sid = try request.data.extract("FaxSid") as String
            let accountSid = try request.data.extract("AccountSid") as String
            guard let account = try Account.collection.findOne("accountSid" == accountSid) else {
                throw ServerAbort(.notFound, reason: "Account not found")
            }
            let authToken = try account.extract("authToken") as String
            
            guard var document = try Fax.collection.findOne("_id" == objectId) else {
                throw ServerAbort(.notFound, reason: "Fax not found")
            }
            
            if request.userId == nil {
                let documentToken = try document.extract("token") as String
                guard token == documentToken else {
                    throw ServerAbort(.notFound, reason: "Invalid fax token")
                }
            }
            
            document["sid"] = sid
            document["accountSid"] = accountSid
            document["from"] = request.data["From"]?.string
            document["to"] = request.data["To"]?.string
            document["remoteStationId"] = request.data["RemoteStationId"]?.string
            document["status"] = request.data["FaxStatus"]?.string
            document["apiVersion"] = request.data["ApiVersion"]?.string
            document["pages"] = request.data["NumPages"]?.int
            document["mediaUrl"] = request.data["OriginalMediaUrl"]?.string
            document["errorCode"] = request.data["ErrorCode"]?.string
            document["errorMessage"] = request.data["ErrorMessage"]?.string
            
            guard let responseBytes = try drop.client.get("\(Constants.Twilio.faxUrl)/Faxes/\(sid)", [
                "Authorization": "Basic \(try String.twilioAuthString(accountSid, authToken: authToken))",
                "Content-Type": "application/x-www-form-urlencoded",
                "Accept": "application/json"
            ]).body.bytes else {
                throw ServerAbort(.notFound, reason: "Error parsing response body")
            }
            let json = try JSON(bytes: responseBytes)
            document.update(withTwilioJson: json)
            
            try Fax.collection.update("_id" == document.objectId, to: document)
            
            if let objectId = document.objectId {
                document.sendAlert(drop, objectId: objectId, to: document["senderEmail"] as? String, subject: "Fax Status Update", alertType: .faxStatus)
            }
            
            return Response(jsonStatus: .ok)
        }
        
        // MARK: Get Fax File
        group.get("file", ":objectId") { request in
            let objectId = try request.parameters.extract("objectId") as ObjectId
            let token = request.data["token"]?.string
            return try getFile(objectId: objectId, token: token, request: request)
        }
        
        // MARK: Get Fax File
        group.get("file", ":objectId", ":token") { request in
            let objectId = try request.parameters.extract("objectId") as ObjectId
            let token = try request.parameters.extract("token") as String
            return try getFile(objectId: objectId, token: token, request: request)
        }
        
        func getFile(objectId: ObjectId, token: String? = nil, request: Request) throws -> Response {
            guard let document = try FaxFile.collection.findOne("faxObjectId" == objectId) else {
                throw ServerAbort(.notFound, reason: "Fax not found")
            }
            
            if request.userId == nil {
                guard let documentToken = document["token"] as? String, token == documentToken else {
                    return Response(redirect: "/user/login?referrer=/fax/file/\(objectId.hexString)")
                }
            }
            
            guard let bytes = Data(document["data"])?.makeBytes() else {
                throw ServerAbort(.notFound, reason: "Fax file empty")
            }
            
            return Response(status: .ok, headers: ["Content-Type": "application/pdf"], body: .data(bytes))
        }
        
        // MARK: Get Faxes
        protected.get { request in
            let phoneNumber = try? request.data.extract("phoneNumber") as String
            let pageInfo = request.pageInfo
            let filter: Query?
            let link: String
            if let phoneNumber = phoneNumber {
                link = "/fax?phoneNumber=\(phoneNumber.urlQueryPercentEncodedPlus)&"
                let query: Query = "from" == phoneNumber || "to" == phoneNumber
                filter = query
            } else {
                link = "/fax?"
                filter = nil
            }
            let documents = try Fax.collection.find(filter, sortedBy: ["dateCreated": .descending], projecting: [
                "sid": false,
                "accountSid": false,
                "url": false,
                "mediaUrl": false,
                "mediaSid": false,
                "apiVersion": false
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
                    let direction = (document["direction"] as? String)?.capitalized ?? ""
                    let status = (document["status"] as? String)?.statusString ?? ""
                    let dateUpdated = document["dateUpdated"] as? Date ?? dateCreated
                    let pages = document["pages"]?.numberString ?? ""
                    let price = document["price"]?.currencyString ?? ""
                    let quality = (document["quality"] as? String)?.quailityString ?? ""
                    let duration = document["duration"]?.intValue?.timeString ?? ""
                    let badge: String
                    if status == "Received" || status == "Delivered" || status == "No Answer" || status == "Busy" {
                        badge = "success"
                    } else if status == "Failed" {
                        badge = "danger"
                    } else {
                        badge = "warning"
                    }
                    let string = "<tr onclick=\"location.href='/fax/file/\(id.hexString)'\"><td>\(direction)</td><td>\(from)</td><td>\(to)</td><td>\(dateCreated.longString)</td><td>\(dateUpdated.longString)</td><td>\(pages)</td><td>\(price)</td><td>\(quality)</td><td>\(duration)</td><td><span class=\"badge badge-\(badge)\">\(status)</span></td></tr>"
                    tableData.append(string)
                }
                return try drop.view.make("faxes", [
                    "tableData": tableData,
                    "accountData": accountData,
                    "pageData": pageData,
                    "page": pageInfo.page,
                    "phoneNumber": phoneNumber ?? "",
                    "nextPage": (pageInfo.page + 1 > pages.count ? "#" : "\(link)page=\(pageInfo.page + 1)"),
                    "prevPage": (pageInfo.page - 1 <= 0 ? "#" : "\(link)page=\(pageInfo.page - 1)")
                ])
            }
        }
        
        // MARK: Receive Fax
        group.post("receive") { request in
            let sid = try request.data.extract("FaxSid") as String
            let accountSid = try request.data.extract("AccountSid") as String
            let mediaUrl = try request.data.extract("MediaUrl") as String
            guard let account = try Account.collection.findOne("accountSid" == accountSid) else {
                throw ServerAbort(.notFound, reason: "Account not found")
            }
            let authToken = try account.extract("authToken") as String
            
            var document: Document = [
                "sid": sid,
                "accountSid": accountSid,
                "from": request.data["From"]?.string,
                "to": request.data["To"]?.string,
                "remoteStationId": request.data["RemoteStationId"]?.string,
                "status": request.data["FaxStatus"]?.string,
                "direction": "inbound",
                "apiVersion": request.data["ApiVersion"]?.string,
                "pages": request.data["NumPages"]?.int,
                "mediaUrl": request.data["MediaUrl"]?.string,
                "errorCode": request.data["ErrorCode"]?.string,
                "errorMessage": request.data["ErrorMessage"]?.string
            ]
            
            guard let responseBytes = try drop.client.get("\(Constants.Twilio.faxUrl)/Faxes/\(sid)", [
                "Authorization": "Basic \(try String.twilioAuthString(accountSid, authToken: authToken))",
                "Content-Type": "application/x-www-form-urlencoded",
                "Accept": "application/json"
            ]).body.bytes else {
                throw ServerAbort(.notFound, reason: "Error parsing response body")
            }
            let json = try JSON(bytes: responseBytes)
            document.update(withTwilioJson: json)
            
            guard let objectId = try Fax.collection.insert(document) as? ObjectId else {
                throw ServerAbort(.notFound, reason: "Error creating fax")
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
                throw ServerAbort(.notFound, reason: "Invalid response")
            }
            
            guard let bytes = response.body.bytes else {
                throw ServerAbort(.notFound, reason: "No response body")
            }
            let fileToken = try String.token()
            
            let fileDocument: Document = [
                "faxObjectId": objectId,
                "token": fileToken,
                "dateCreated": Date(),
                "data": Data(bytes: bytes)
            ]
            
            try FaxFile.collection.insert(fileDocument)
            
            document.sendAlert(drop, objectId: objectId, to: account["notificationEmail"] as? String ?? Admin.settings.notificationEmail, subject: "Fax Received", alertType: .faxStatus)
            
            return Response(jsonStatus: .ok)
        }
    }
}
