//
//  Message+Routes.swift
//  Server
//
//  Created by BluDesign, LLC on 8/25/17.
//

import Foundation
import Vapor
import MongoKitten
import Leaf

private extension Document {
    
    // MARK: - Methods
    
    private func stringValue(_ key: String) -> String {
        return self[key] as? String ?? "Unknown"
    }
    
    mutating func update(withMessage message: TwilioMessage) {
        self["sid"] = message.sid
        self["accountSid"] = message.accountSid
        self["status"] = message.status ?? self["status"]
        self["messagingServiceId"] = message.messagingServiceId ?? self["messagingServiceId"]
        self["from"] = message.from ?? self["from"]
        self["to"] = message.to ?? self["to"]
        self["mediaCount"] = message.mediaCount?.intValue ?? self["mediaCount"]
        self["segments"] = message.segmentCount?.intValue ?? self["segments"]
        self["price"] = message.price?.doubleValue ?? self["price"]
        self["priceUnit"] = message.priceUnit ?? self["priceUnit"]
        self["apiVersion"] = message.apiVersion ?? self["apiVersion"]
    }
    
    mutating func update(withIncommingMessage message: TwilioIncommingMessage) {
        self["sid"] = message.sid
        self["accountSid"] = message.accountSid
        self["from"] = message.from ?? self["from"]
        self["to"] = message.to ?? self["to"]
        self["body"] = message.body ?? self["body"]
        self["messagingServiceId"] = message.messagingServiceId ?? self["messagingServiceId"]
        self["mediaCount"] = message.mediaCount ?? self["mediaCount"]
        self["segmentCount"] = message.segmentCount ?? self["segmentCount"]
        self["status"] = message.status ?? self["status"]
        self["apiVersion"] = message.apiVersion ?? self["apiVersion"]
        self["fromCity"] = message.fromCity ?? self["fromCity"]
        self["fromState"] = message.fromState ?? self["fromState"]
        self["fromZip"] = message.fromZip ?? self["fromZip"]
        self["fromCountry"] = message.fromCountry ?? self["fromCountry"]
        self["toCity"] = message.toCity ?? self["toCity"]
        self["toState"] = message.toState ?? self["toState"]
        self["toZip"] = message.toZip ?? self["toZip"]
        self["toCountry"] = message.toCountry ?? self["toCountry"]
        self["errorCode"] = message.errorCode ?? self["errorCode"]
        self["errorMessage"] = message.errorMessage ?? self["errorMessage"]
    }
    
    func sendAlert(_ request: Request, objectId: ObjectId, to: String?, subject: String) {
        if Admin.settings.messageSendEmail, let to = to {
            sendEmail(request, objectId: objectId, to: to, subject: subject)
        }
        if Admin.settings.messageSendApns {
            sendPush(objectId: objectId, subject: subject)
        }
        if Admin.settings.messageSendSlack {
            sendSlack(request, objectId: objectId, subject: subject)
        }
    }
    
    private func sendEmail(_ request: Request, objectId: ObjectId, to: String, subject: String) {
        let context = TemplateData.dictionary([
            "title": .string(subject),
            "from": .string(stringValue("from")),
            "to": .string(stringValue("to")),
            "date": .string((self["dateCreated"] as? Date)?.longString ?? "Unknown"),
            "body": .string(stringValue("body"))
        ])
        do {
            _ = try request.make(LeafRenderer.self).render("faxStatusEmail", context).do { (view) in
                do {
                    try Email.send(subject: subject, to: to, htmlBody: view.data, redirect: nil, request: request, promise: nil)
                } catch let error {
                    Logger.error("Error Sending Email: \(error)")
                }
            }
        } catch let error {
            Logger.error("Error Sending Email: \(error)")
        }
    }
    
    private func sendPush(objectId: ObjectId, subject: String) {
        if let from = self["from"] as? String {
            let mediaCount = self["mediaCount"]?.intValue ?? 0
            let body = (self["body"] as? String) ?? (mediaCount > 0 ? "Image" : "")
            PushProvider.sendPush(title: from, body: body)
        }
    }
    
    private func sendSlack(_ request: Request, objectId: ObjectId, subject: String) {
        guard let from = self["from"] as? String, let url = Admin.settings.domain else { return }
        let mediaCount = self["mediaCount"]?.intValue ?? 0
        let body = (self["body"] as? String) ?? (mediaCount > 0 ? "Image" : "")
        PushProvider.sendSlack(objectName: "Message", objectLink: "\(url)/fax/message", title: body, titleLink: "\(url)/message", isError: false, date: self["dateCreated"] as? Date ?? Date(), fields: [
            (title: "From", value: from)
        ])
    }
}


struct MessageRouter {
    
    init(router: Router) {
        let protectedRouter = router.grouped(AuthenticationMiddleware.self)
        
        router.post("twiml", use: postTwiml)
        protectedRouter.post(use: post)
        protectedRouter.get(use: get)
        protectedRouter.get(ObjectId.parameter, use: getMessage)
        protectedRouter.delete(ObjectId.parameter, use: deleteMessage)
        protectedRouter.post(ObjectId.parameter, use: deleteMessage)
        router.post("nexmo", use: postNexmo)
        router.get("file", ObjectId.parameter, use: getFileFileId)
        router.get("file", ObjectId.parameter, String.parameter, use: getFileFileIdToken)
        router.post("status", ObjectId.parameter, use: postStatusFaxId)
        router.post("status", ObjectId.parameter, String.parameter, use: postStatusFaxIdToken)
    }
    
    // MARK: POST twiml
    func postTwiml(_ request: Request) throws -> Future<ServerResponse> {
        return request.globalAsync { promise in
            Logger.info("In: \(request)")
            let message = try request.content.syncDecode(TwilioIncommingMessage.self)
            guard let account = try Account.collection.findOne("accountSid" == message.accountSid) else {
                throw ServerAbort(.notFound, reason: "Account not found")
            }
            
            var document: Document = [
                "sid": message.sid,
                "accountSid": message.accountSid,
                "from": message.from,
                "to": message.to,
                "messagingServiceId": message.messagingServiceId,
                "body": message.body,
                "mediaCount": message.mediaCount,
                "segmentCount": message.segmentCount,
                "errorCode": message.errorCode,
                "errorMessage": message.errorMessage,
                "direction": "inbound",
                "status": "received",
                "dateCreated": Date()
            ]
            
            document["fromCity"] = message.fromCity
            document["fromState"] = message.fromState
            document["fromZip"] = message.fromZip
            document["fromCountry"] = message.fromCountry
            document["toCity"] = message.toCity
            document["toState"] = message.toState
            document["toZip"] = message.toZip
            document["toCountry"] = message.toCountry
            
            guard let objectId = try Message.collection.insert(document) as? ObjectId else {
                throw ServerAbort(.notFound, reason: "Error creating message")
            }
            
            func complete() {
                document.sendAlert(request, objectId: objectId, to: account["notificationEmail"] as? String ?? Admin.settings.notificationEmail, subject: "Message Received")
                let responseString = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><Response></Response>"
                let response = Response(using: request.sharedContainer)
                response.http.headers.replaceOrAdd(name: .contentType, value: "text/xml")
                response.http.body = HTTPBody(data: responseString.convertToData())
                response.http.status = .ok
                return promise.succeed(result: ServerResponse.response(response))
            }
            
            if let mediaItems = message.mediaItems {
                let requestClient = try request.make(Client.self)
                func getMedia(mediaUrl: String, count: Int = 0, callback: @escaping (Response) -> ()) {
                    _ = requestClient.get(mediaUrl).do { response in
                        if response.http.status == .ok {
                            callback(response)
                        } else {
                            guard count <= 5, let url = response.http.headers.firstValue(name: .location) else {
                                callback(response)
                                return
                            }
                            getMedia(mediaUrl: url, count: count + 1, callback: callback)
                        }
                    }
                }
                func getMediaIndex(mediaIndex: Int, callback: @escaping (Error?) -> ()) {
                    let mediaItem = mediaItems[mediaIndex]
                    getMedia(mediaUrl: mediaItem.url, count: 0) { mediaResponse in
                        do {
                            guard mediaResponse.http.status == .ok, let data = mediaResponse.http.body.data else {
                                throw ServerAbort(.notFound, reason: "Error getting message media")
                            }
                            let fileToken = try String.token()
                            let fileDocument: Document = [
                                "messageObjectId": objectId,
                                "token": fileToken,
                                "dateCreated": Date(),
                                "mimeType": mediaItem.contentType,
                                "mediaNumber": mediaIndex,
                                "data": data
                            ]
                            try MessageFile.collection.insert(fileDocument)
                            if mediaIndex == mediaItems.count - 1 {
                                callback(nil)
                            } else {
                                getMediaIndex(mediaIndex: mediaIndex + 1, callback: callback)
                            }
                        } catch let error {
                            Logger.error("Fax Receive Error: \(error)")
                            callback(error)
                        }
                    }
                }
                getMediaIndex(mediaIndex: 0) { (error) in
                    if let error = error {
                        return promise.fail(error: error)
                    } else {
                        complete()
                    }
                }
            } else {
                complete()
            }
        }
    }
    
    // MARK: POST
    func post(_ request: Request) throws -> Future<ServerResponse> {
        let authentication = try request.authentication()
        guard authentication.permission != .readOnly else {
            return try request.statusRedirectEncoded(status: .forbidden, to: "/message")
        }
        let promise = request.eventLoop.newPromise(ServerResponse.self)
        struct FormData: Content {
            let to: String
            let from: String?
            let body: String?
            let accountId: ObjectId
            let file: File?
        }
        _ = try request.content.decode(FormData.self).do { (formData) in
            DispatchQueue.global().async {
                do {
                    guard let account = try Account.collection.findOne("_id" == formData.accountId) else {
                        throw ServerAbort(.notFound, reason: "Account not found")
                    }
                    let accountSid = try account.extract("accountSid") as String
                    let authToken = try account.extract("authToken") as String
                    let phoneNumber = try account.extract("phoneNumber") as String
                    let token = try String.token()
                    let fromString = formData.from ?? phoneNumber
                    
                    var document: Document = [
                        "from": fromString,
                        "to": formData.to,
                        "userId": authentication.userId,
                        "body": formData.body,
                        "token": token,
                        "accountSid": accountSid,
                        "direction": "outbound",
                        "status": "started",
                        "dateCreated": Date(),
                        "accountId": formData.accountId
                    ]
                    guard let objectId = try Message.collection.insert(document) as? ObjectId else {
                        throw ServerAbort(.internalServerError, reason: "Error creating message")
                    }
                    guard let url = Admin.settings.domain else {
                        throw ServerAbort(.notFound, reason: "No host URL set in settings")
                    }
                    
                    let mediaUrl: String?
                    if let file = formData.file, let contentType = file.contentType {
                        guard contentType == .png || contentType == .jpeg || contentType == .gif else {
                            throw ServerAbort(.badRequest, reason: "Invalid file format must be an image")
                        }
                        let fileDocument: Document = [
                            "messageObjectId": objectId,
                            "token": token,
                            "dateCreated": Date(),
                            "mimeType": contentType.serialize(),
                            "data": file.data,
                            "fileName": file.filename
                        ]
                        guard let fileObjectId = try MessageFile.collection.insert(fileDocument) as? ObjectId else {
                            throw ServerAbort(.notFound, reason: "Error creating message file")
                        }
                        mediaUrl = "\(url)/message/file/\(fileObjectId.hexString)/\(token)"
                    } else {
                        mediaUrl = nil
                    }
                    
                    guard mediaUrl != nil || formData.body != nil else {
                        throw ServerAbort(.badRequest, reason: "Message must have a body or attachment")
                    }
                    let requestClient = try request.make(Client.self)
                    let headers = HTTPHeaders([
                        ("Authorization", "Basic \(try String.twilioAuthString(accountSid, authToken: authToken))"),
                        ("Content-Type", "application/x-www-form-urlencoded"),
                        ("Accept", "application/json")
                    ])
                    var content: [String: String] = [
                        "From": fromString,
                        "To": formData.to,
                        "StatusCallback": "\(url)/message/status/\(objectId.hexString)/\(token)"
                    ]
                    if let mediaUrl = mediaUrl {
                        content["MediaUrl"] = mediaUrl
                    }
                    if let body = formData.body {
                        content["Body"] = body
                    }
                    requestClient.post("\(Constants.Twilio.messageUrl)/Accounts/\(accountSid)/Messages.json", headers: headers, beforeSend: { request in
                        try request.content.encode(content, as: .urlEncodedForm)
                    }).do { response in
                        do {
                            guard response.http.status.isValid else {
                                document["status"] = "failed"
                                try Message.collection.update("_id" == objectId, to: document)
                                if let error = try? response.content.syncDecode(TwilioError.self) {
                                    throw ServerAbort(response.http.status, reason: "\(error.code): \(error.message)")
                                }
                                throw ServerAbort(response.http.status, reason: "Twilio reponse error")
                            }
                            
                            let message = try response.content.syncDecode(TwilioMessage.self)
                            document.update(withMessage: message)
                            
                            try Message.collection.update("_id" == objectId, to: document)
                            
                            if request.jsonResponse {
                                return promise.submit(try document.makeResponse(request))
                            }
                            return promise.succeed(result: request.serverStatusRedirect(status: .ok, to: "/message/\(objectId.hexString)"))
                        } catch let error {
                            return promise.fail(error: error)
                        }
                        }.catch { error in
                            return promise.fail(error: error)
                    }
                } catch let error {
                    return promise.fail(error: error)
                }
            }
        }
        return promise.futureResult
    }
    
    // MARK: GET
    func get(_ request: Request) throws -> Future<ServerResponse> {
        return request.globalAsync { promise in
            let authentication = try request.authentication()
            let phoneNumber = try? request.query.get(at: "phoneNumber") as String
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
                return promise.submit(try documents.makeResponse(request))
            } else {
                var pageLink: String = ""
                if let phoneNumber = phoneNumber {
                    pageLink += "&phoneNumber=\(phoneNumber)"
                }
                let pageSkip = max(pageInfo.skip - (pageInfo.limit * 5), 0)
                var pages = try ((pageSkip + documents.count(limitedTo: pageInfo.limit * 10, skipping: pageSkip)) / pageInfo.limit) + 1
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
                    let mediaCount = document["mediaCount"]?.numberString ?? ""
                    let string = "<tr onclick=\"location.href='/message/\(id.hexString)'\"><td>\(from)</td><td>\(to)</td><td>\(dateCreated.longString)</td><td>\(body)</td><td>\(mediaCount)</td><td><span class=\"badge badge-\(badge)\">\(status)</span></td></tr>"
                    tableData.append(string)
                }
                let context = TemplateData.dictionary([
                    "tableData": .string(tableData),
                    "accountData": .string(accountData),
                    "phoneNumber": .string(phoneNumber ?? ""),
                    "pageData": .string(pageData),
                    "page": .int(pageInfo.page),
                    "nextPage": .string((pageInfo.page + 1 > pages ? "#" : "\(link)page=\(pageInfo.page + 1)\(pageLink)")),
                    "prevPage": .string((pageInfo.page - 1 <= 0 ? "#" : "\(link)page=\(pageInfo.page - 1)\(pageLink)")),
                    "admin": .bool(authentication.permission.isAdmin),
                    "canSend": .bool(authentication.permission != .readOnly),
                    "contactsEnabled": .bool(Admin.settings.googleClientId != nil && Admin.settings.googleClientSecret != nil)
                ])
                return promise.submit(try request.renderEncoded("messages", context))
            }
        }
    }
    
    // MARK: GET :messageId
    func getMessage(_ request: Request) throws -> Future<ServerResponse> {
        return request.globalAsync { promise in
            let objectId = try request.parameters.next(ObjectId.self)
            let authentication = try request.authentication()
            
            guard let document = try Message.collection.findOne("_id" == objectId, projecting: [
                "sid": false,
                "accountSid": false,
                "messagingServiceId": false
            ]) else {
                throw ServerAbort(.notFound, reason: "Message not found")
            }
            
            if request.jsonResponse {
                return promise.submit(try document.makeResponse(request))
            } else {
                let from = document["from"] as? String ?? "Unknown"
                let to = document["to"] as? String ?? "Unknown"
                let dateCreated = (document["dateCreated"] as? Date)?.longString ?? "Unknown"
                let body = document["body"] as? String ?? ""
                let mediaCount = document["mediaCount"]?.numberString ?? ""
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
                    toLocation = "Unknown"
                }
                let fromLocation: String
                if let city = document["fromCity"] as? String, let state = document["fromState"] as? String, let country = document["fromCountry"] as? String {
                    fromLocation = "\(city), \(state), \(country)"
                } else {
                    fromLocation = "Unknown"
                }
                
                var mediaFiles = ""
                if document["mediaCount"]?.intValue ?? 0 > 0 {
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
                
                var contextDictionary: [String: TemplateData] = [
                    "messageId": .string(objectId.hexString),
                    "from": .string(from),
                    "to": .string(to),
                    "fromLocation": .string(fromLocation),
                    "toLocation": .string(toLocation),
                    "date": .string(dateCreated),
                    "status": .string("<span class=\"badge badge-\(badge)\">\(status)</span>"),
                    "mediaCount": .string(mediaCount),
                    "body": .string(body),
                    "mediaFiles": .string(mediaFiles),
                    "admin": .bool(authentication.permission.isAdmin),
                    "canDelete": .bool((Admin.settings.regularUserCanDelete ? authentication.permission != .readOnly : authentication.permission.isAdmin)),
                    "contactsEnabled": .bool(Admin.settings.googleClientId != nil && Admin.settings.googleClientSecret != nil)
                ]
                if let userId = document["userId"] as? ObjectId, let user = try User.collection.findOne("_id" == userId, projecting: [
                    "email": true
                ]), let userEmail = user["email"] as? String {
                    contextDictionary["sendingUser"] = .string(userEmail)
                }
                let context = TemplateData.dictionary(contextDictionary)
                return promise.submit(try request.renderEncoded("message", context))
            }
        }
    }
    
    // MARK: DELETE :messageId
    func deleteMessage(_ request: Request) throws -> Future<ServerResponse> {
        return request.globalAsync { promise in
            let objectId = try request.parameters.next(ObjectId.self)
            let authentication = try request.authentication()
            guard (Admin.settings.regularUserCanDelete ? authentication.permission != .readOnly : authentication.permission.isAdmin) else {
                return promise.succeed(result: request.serverStatusRedirect(status: .forbidden, to: "/message/\(objectId.hexString)"))
            }
            try MessageFile.collection.remove("messageObjectId" == objectId)
            try Message.collection.remove("_id" == objectId)
            return promise.succeed(result: request.serverStatusRedirect(status: .ok, to: "/message"))
        }
    }
    
    // MARK: GET file/:fileId
    func getFileFileId(_ request: Request) throws -> Future<ServerResponse> {
        let objectId = try request.parameters.next(ObjectId.self)
        let token = try? request.query.get(at: "token") as String
        return try getFile(objectId: objectId, token: token, request: request)
    }
    
    // MARK: GET file/:fileId/:token
    func getFileFileIdToken(_ request: Request) throws -> Future<ServerResponse> {
        let objectId = try request.parameters.next(ObjectId.self)
        let token = try request.parameters.next(String.self)
        return try getFile(objectId: objectId, token: token, request: request)
    }
    
    func getFile(objectId: ObjectId, token: String? = nil, request: Request) throws -> Future<ServerResponse> {
        return request.globalAsync { promise in
            guard let document = try MessageFile.collection.findOne("_id" == objectId) else {
                throw ServerAbort(.notFound, reason: "Message not found")
            }
            
            if (try? request.authentication()) == nil {
                guard let documentToken = document["token"] as? String, token == documentToken else {
                    return promise.succeed(result: request.serverStatusRedirect(status: .forbidden, to: "/user/login?referrer=/message/file/\(objectId.hexString)"))
                }
            }
            
            let mimeType = try document.extract("mimeType") as String
            guard let data = Data(document["data"]) else {
                throw ServerAbort(.notFound, reason: "Message file empty")
            }
            
            let response = Response(using: request.sharedContainer)
            response.http.headers.replaceOrAdd(name: .contentType, value: mimeType)
            response.http.status = .ok
            response.http.body = HTTPBody(data: data)
            return promise.succeed(result: ServerResponse.response(response))
        }
    }
    
    // MARK: POST status/:faxId
    func postStatusFaxId(_ request: Request) throws -> Future<ServerResponse> {
        let objectId = try request.parameters.next(ObjectId.self)
        let token = try? request.query.get(at: "token") as String
        return try status(objectId: objectId, token: token, request: request)
    }
    // MARK: POST status/:faxId/:token
    func postStatusFaxIdToken(_ request: Request) throws -> Future<ServerResponse> {
        let objectId = try request.parameters.next(ObjectId.self)
        let token = try request.parameters.next(String.self)
        return try status(objectId: objectId, token: token, request: request)
    }
    
    func status(objectId: ObjectId, token: String? = nil, request: Request) throws -> Future<ServerResponse> {
        return request.globalAsync { promise in
            let message = try request.content.syncDecode(TwilioIncommingMessage.self)
            
            guard var document = try Message.collection.findOne("_id" == objectId) else {
                throw ServerAbort(.notFound, reason: "Message not found")
            }
            
            if (try? request.authentication()) == nil {
                let documentToken = try document.extract("token") as String
                guard token == documentToken else {
                    throw ServerAbort(.notFound, reason: "Invalid fax token")
                }
            }
            
            document.update(withIncommingMessage: message)
            try Message.collection.update("_id" == document.objectId, to: document)
            
            return promise.succeed(result: ServerResponse.response(request.statusResponse(status: .ok)))
        }
    }
    
    // MARK: POST nexmo
    func postNexmo(_ request: Request) throws -> Future<ServerResponse> {
        return request.globalAsync { promise in
            guard Admin.settings.nexmoEnabled else {
                throw ServerAbort(.notFound, reason: "Nexmo is disabled")
            }
            struct FormData: Codable {
                let msisdn: String
                let to: String
                let messageId: String
                let text: String
                let type: String
            }
            let formData = try request.content.syncDecode(FormData.self)
            let document: Document = [
                "sid": formData.messageId,
                "from": formData.msisdn,
                "to": formData.to,
                "body": formData.text,
                "direction": "inbound",
                "status": "received",
                "dateCreated": Date()
            ]
            
            guard let objectId = try Message.collection.insert(document) as? ObjectId else {
                throw ServerAbort(.notFound, reason: "Error creating message")
            }
            
            document.sendAlert(request, objectId: objectId, to: Admin.settings.notificationEmail, subject: "Message Received")
            
            return promise.succeed(result: ServerResponse.response(request.statusResponse(status: .ok)))
        }
    }
}
