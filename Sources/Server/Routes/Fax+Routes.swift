//
//  Fax+Routes.swift
//  Server
//
//  Created by BluDesign, LLC on 6/29/17.
//

import Foundation
import Vapor
import MongoKitten
import Leaf

private enum AlertType {
    case faxReceived, faxStatus
}

private extension Document {

    // MARK: - Methods

    private func stringValue(_ key: String) -> String {
        return self[key] as? String ?? "Unknown"
    }

    mutating func update(withFax fax: TwilioFax) {
        self["sid"] = fax.sid
        self["accountSid"] = fax.accountSid
        self["mediaSid"] = fax.mediaSid ?? self["mediaSid"]
        self["status"] = fax.status ?? self["status"]
        self["direction"] = fax.direction ?? self["direction"]
        self["from"] = fax.from ?? self["from"]
        self["to"] = fax.to ?? self["to"]
        self["dateUpdated"] = fax.dateUpdated ?? self["dateUpdated"]
        self["price"] = fax.price?.doubleValue ?? self["price"]
        self["dateCreated"] = fax.dateCreated ?? self["dateCreated"]
        self["url"] = fax.url ?? self["url"]
        self["duration"] = fax.duration ?? self["duration"]
        self["pages"] = fax.pages ?? self["pages"]
        self["quality"] = fax.quality ?? self["quality"]
        self["priceUnit"] = fax.priceUnit ?? self["priceUnit"]
        self["apiVersion"] = fax.apiVersion ?? self["apiVersion"]
        self["mediaUrl"] = fax.mediaUrl ?? self["mediaUrl"]
    }
    
    mutating func update(withIncommingFax fax: TwilioIncommingFax) {
        self["sid"] = fax.sid
        self["accountSid"] = fax.accountSid
        self["status"] = fax.status ?? self["status"]
        self["from"] = fax.from ?? self["from"]
        self["to"] = fax.to ?? self["to"]
        self["pages"] = fax.pages ?? self["pages"]
        self["apiVersion"] = fax.apiVersion ?? self["apiVersion"]
        self["remoteStationId"] = fax.remoteStationId ?? self["remoteStationId"]
        self["mediaUrl"] = fax.mediaUrl ?? self["mediaUrl"]
        self["errorCode"] = fax.errorCode ?? self["errorCode"]
        self["errorMessage"] = fax.errorMessage ?? self["errorMessage"]
    }

    func sendAlert(_ request: Request, objectId: ObjectId, to: String?, subject: String, alertType: AlertType) {
        if (alertType == .faxStatus ? Admin.settings.faxStatusSendEmail : Admin.settings.faxReceivedSendEmail), let to = to {
            sendEmail(request, objectId: objectId, to: to, subject: subject)
        }
        if (alertType == .faxStatus ? Admin.settings.faxStatusSendApns : Admin.settings.faxReceivedSendApns) {
            sendPush(objectId: objectId, subject: subject)
        }
        if (alertType == .faxStatus ? Admin.settings.faxStatusSendSlack : Admin.settings.faxReceivedSendSlack) {
            sendSlack(request, objectId: objectId, subject: subject)
        }
    }

    private func sendEmail(_ request: Request, objectId: ObjectId, to: String, subject: String) {
        guard let url = Admin.settings.domain else {
            Logger.error("Error Sending Email: No host URL set in settings")
            return
        }
        let context = TemplateData.dictionary([
            "title": .string(subject),
            "status": .string(stringValue("status").capitalized),
            "from": .string(stringValue("from")),
            "to": .string(stringValue("to")),
            "date": .string((self["dateCreated"] as? Date)?.longString ?? "Unknown"),
            "direction": .string(stringValue("direction").capitalized),
            "quality": .string(stringValue("quality").capitalized),
            "pages": .string(self["pages"]?.numberString ?? ""),
            "duration": .string(self["duration"]?.intValue?.timeString ?? ""),
            "mediaUrl": .string("\(url)/fax/file/\(objectId.hexString)"),
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
        if let from = self["from"] as? String, let to = self["to"] as? String, let status = (self["status"] as? String)?.capitalized {
            PushProvider.sendPush(title: subject, body: "Status: \(status) From: \(from) To: \(to)")
        }
    }

    private func sendSlack(_ request: Request, objectId: ObjectId, subject: String) {
        guard let url = Admin.settings.domain else {
            Logger.error("Error Sending Email: No host URL set in settings")
            return
        }
        guard let from = self["from"] as? String, let to = self["to"] as? String, let status = (self["status"] as? String)?.capitalized else { return }
        PushProvider.sendSlack(objectName: "Fax", objectLink: "\(url)/fax/\(objectId.hexString)", title: subject, titleLink: "\(url)/fax/file/\(objectId.hexString)", isError: false, date: self["dateCreated"] as? Date ?? Date(), fields: [
            (title: "Status", value: status),
            (title: "From", value: from),
            (title: "To", value: to)
        ])
    }
}

struct FaxRouter {
    
    init(router: Router) {
        let protectedRouter = router.grouped(AuthenticationMiddleware.self)
        
        router.post("twiml", use: postTwiml)
        protectedRouter.post(use: post)
        protectedRouter.get(use: get)
        protectedRouter.get(ObjectId.parameter, use: getFax)
        protectedRouter.delete(ObjectId.parameter, use: deleteFax)
        protectedRouter.post(ObjectId.parameter, use: deleteFax)
        router.get("file", ObjectId.parameter, use: getFileFileId)
        router.get("file", ObjectId.parameter, String.parameter, use: getFileFileIdToken)
        router.post("status", ObjectId.parameter, use: postStatusFaxId)
        router.post("status", ObjectId.parameter, String.parameter, use: postStatusFaxIdToken)
        router.post("receive", use: postReceive)
    }
    
    // MARK: POST twiml
    func postTwiml(_ request: Request) throws -> ServerResponse {
        guard let url = Admin.settings.domain else {
            throw ServerAbort(.notFound, reason: "No host URL set in settings")
        }
        let responseString = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><Response><Receive action=\"\(url)/fax/receive\"/></Response>"
        
        let response = Response(using: request.sharedContainer)
        response.http.headers.replaceOrAdd(name: .contentType, value: "text/xml")
        response.http.body = HTTPBody(data: responseString.convertToData())
        response.http.status = .ok
        return ServerResponse.response(response)
    }
    
    // MARK: POST
    func post(_ request: Request) throws -> Future<ServerResponse> {
        let authentication = try request.authentication()
        guard authentication.permission != .readOnly else {
            return try request.statusRedirectEncoded(status: .forbidden, to: "/fax")
        }
        let promise = request.eventLoop.newPromise(ServerResponse.self)
        struct FormData: Content, Validatable {
            let to: String
            let from: String?
            let senderEmail: String
            let accountId: ObjectId
            let file: File
            
            static func validations() throws -> Validations<FormData> {
                var validations = Validations(FormData.self)
                validations.add(\FormData.senderEmail, at: ["senderEmail"], Validator.email)
                return validations
            }
        }
        _ = try request.content.decode(FormData.self).do { (formData) in
            DispatchQueue.global().async {
                do {
                    try formData.validate()
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
                        "token": token,
                        "accountSid": accountSid,
                        "senderEmail": formData.senderEmail,
                        "status": "started",
                        "dateCreated": Date(),
                        "accountId": formData.accountId,
                        "direction": "outbound"
                    ]
                    guard let objectId = try Fax.collection.insert(document) as? ObjectId else {
                        throw ServerAbort(.internalServerError, reason: "Error creating fax")
                    }
                    guard formData.file.contentType == .pdf else {
                        throw ServerAbort(.badRequest, reason: "Invalid file format must be an PDF")
                    }
                    
                    let fileDocument: Document = [
                        "faxObjectId": objectId,
                        "token": token,
                        "dateCreated": Date(),
                        "fileName": formData.file.filename,
                        "data": formData.file.data
                    ]
                    try FaxFile.collection.insert(fileDocument)
                    
                    
                    let requestClient = try request.make(Client.self)
                    let headers = HTTPHeaders([
                        ("Authorization", "Basic \(try String.twilioAuthString(accountSid, authToken: authToken))"),
                        ("Content-Type", "application/x-www-form-urlencoded"),
                        ("Accept", "application/json")
                    ])
                    guard let url = Admin.settings.domain else {
                        throw ServerAbort(.notFound, reason: "No host URL set in settings")
                    }
                    let content: [String: String] = [
                        "From": fromString,
                        "To": formData.to,
                        "MediaUrl": "\(url)/fax/file/\(objectId.hexString)/\(token)",
                        "StatusCallback": "\(url)/fax/status/\(objectId.hexString)/\(token)"
                    ]
                    requestClient.post("\(Constants.Twilio.faxUrl)/Faxes", headers: headers, beforeSend: { request in
                        try request.content.encode(content, as: .urlEncodedForm)
                    }).do { response in
                        do {
                            guard response.http.status.isValid else {
                                document["status"] = "failed"
                                try Fax.collection.update("_id" == objectId, to: document)
                                throw ServerAbort(response.http.status, reason: "Twilio reponse error")
                            }
                            
                            let fax = try response.content.syncDecode(TwilioFax.self)
                            document.update(withFax: fax)
                            
                            try Fax.collection.update("_id" == objectId, to: document)
                            
                            document.sendAlert(request, objectId: objectId, to: formData.senderEmail, subject: "Fax Sent", alertType: .faxStatus)
                            if request.jsonResponse {
                                return promise.submit(try document.makeResponse(request))
                            }
                            return promise.succeed(result: request.serverStatusRedirect(status: .ok, to: "/fax/\(objectId.hexString)"))
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
    
    // MARK: GET :faxId
    func getFax(_ request: Request) throws -> Future<ServerResponse> {
        return request.globalAsync { promise in
            let objectId = try request.parameters.next(ObjectId.self)
            let authentication = try request.authentication()
            
            guard let document = try Fax.collection.findOne("_id" == objectId, projecting: [
                "sid": false,
                "accountSid": false,
                "mediaSid": false
            ]) else {
                throw ServerAbort(.notFound, reason: "Fax not found")
            }
            
            if request.jsonResponse {
                return promise.submit(try document.makeResponse(request))
            } else {
                let from = document["from"] as? String ?? "Unknown"
                let to = document["to"] as? String ?? "Unknown"
                let dateCreated = (document["dateCreated"] as? Date)?.longString ?? "Unknown"
                let dateUpdated = (document["dateUpdated"] as? Date)?.longString ?? "Unknown"
                let status = (document["status"] as? String)?.statusString ?? "Unknown"
                let badge: String
                if status == "Received" || status == "Delivered" {
                    badge = "success"
                } else if status == "Failed" {
                    badge = "danger"
                } else {
                    badge = "warning"
                }
                let direction = (document["direction"] as? String)?.capitalized ?? "Unknown"
                let quality = (document["quality"] as? String)?.quailityString ?? "Unknown"
                let remoteStationId = (document["remoteStationId"] as? String) ?? "None"
                let pages = document["pages"]?.numberString ?? "Unknown"
                let duration = document["duration"]?.numberString ?? "Unknown"
                let price: String
                if let priceValue = document["price"]?.currencyString {
                    if let priceUnit = (document["priceUnit"] as? String) {
                        price = "\(priceValue) (\(priceUnit))"
                    } else {
                        price = priceValue
                    }
                } else {
                    price = "None"
                }
                
                var contextDictionary: [String: TemplateData] = [
                    "faxId": .string(objectId.hexString),
                    "from": .string(from),
                    "to": .string(to),
                    "dateCreated": .string(dateCreated),
                    "dateUpdated": .string(dateUpdated),
                    "status": .string("<span class=\"badge badge-\(badge)\">\(status)</span>"),
                    "direction": .string(direction),
                    "quality": .string(quality),
                    "pages": .string(pages),
                    "duration": .string(duration),
                    "price": .string(price),
                    "remoteStationId": .string(remoteStationId),
                    "admin": .bool(authentication.permission.isAdmin),
                    "canDelete": .bool((Admin.settings.regularUserCanDelete ? authentication.permission != .readOnly : authentication.permission.isAdmin)),
                    "contactsEnabled": .bool(Admin.settings.googleClientId != nil && Admin.settings.googleClientSecret != nil)
                ]
                if let userId = document["userId"] as? ObjectId, let user = try User.collection.findOne("_id" == userId, projecting: [
                    "email": true
                ]), let userEmail = user["email"] as? String {
                    contextDictionary["sendingUser"] = .string(userEmail)
                }
                if let errorCode = document["errorCode"] as? String, let errorMessage = document["errorMessage"] as? String {
                    contextDictionary["error"] = .string("\(errorCode) - \(errorMessage)")
                }
                let context = TemplateData.dictionary(contextDictionary)
                return promise.submit(try request.renderEncoded("fax", context))
            }
        }
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
                    let string = "<tr onclick=\"location.href='/fax/\(id.hexString)'\"><td>\(direction)</td><td>\(from)</td><td>\(to)</td><td>\(dateCreated.longString)</td><td>\(dateUpdated.longString)</td><td>\(pages)</td><td>\(price)</td><td>\(quality)</td><td>\(duration)</td><td><span class=\"badge badge-\(badge)\">\(status)</span></td><td><a href=\"/fax/file/\(id.hexString)\">PDF</a></td></tr>"
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
                return promise.submit(try request.renderEncoded("faxes", context))
            }
        }
    }
    
    // MARK: DELETE :faxId
    func deleteFax(_ request: Request) throws -> Future<ServerResponse> {
        return request.globalAsync { promise in
            let objectId = try request.parameters.next(ObjectId.self)
            let authentication = try request.authentication()
            guard (Admin.settings.regularUserCanDelete ? authentication.permission != .readOnly : authentication.permission.isAdmin) else {
                return promise.succeed(result: request.serverStatusRedirect(status: .forbidden, to: "/fax/\(objectId.hexString)"))
            }
            try FaxFile.collection.remove("faxObjectId" == objectId)
            try Fax.collection.remove("_id" == objectId)
            return promise.succeed(result: request.serverStatusRedirect(status: .ok, to: "/fax"))
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
            guard let document = try FaxFile.collection.findOne("faxObjectId" == objectId) else {
                throw ServerAbort(.notFound, reason: "Fax not found")
            }
            if (try? request.authentication()) == nil {
                guard let documentToken = document["token"] as? String, token == documentToken else {
                    return promise.succeed(result: request.serverStatusRedirect(status: .forbidden, to: "/user/login?referrer=/fax/file/\(objectId.hexString)"))
                }
            }
            
            guard let data = Data(document["data"]) else {
                throw ServerAbort(.notFound, reason: "Fax file empty")
            }
            
            let response = Response(using: request.sharedContainer)
            response.http.headers.replaceOrAdd(name: .contentType, value: "application/pdf")
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
            let twilioFax = try request.content.syncDecode(TwilioIncommingFax.self)
            guard let account = try Account.collection.findOne("accountSid" == twilioFax.accountSid) else {
                throw ServerAbort(.notFound, reason: "Account not found")
            }
            let authToken = try account.extract("authToken") as String
            
            guard var document = try Fax.collection.findOne("_id" == objectId) else {
                throw ServerAbort(.notFound, reason: "Fax not found")
            }
            
            if (try? request.authentication()) == nil {
                let documentToken = try document.extract("token") as String
                guard token == documentToken else {
                    throw ServerAbort(.notFound, reason: "Invalid fax token")
                }
            }
            
            document.update(withIncommingFax: twilioFax)
            
            let requestClient = try request.make(Client.self)
            let headers = HTTPHeaders([
                ("Authorization", "Basic \(try String.twilioAuthString(twilioFax.accountSid, authToken: authToken))"),
                ("Accept", "application/json")
            ])
            requestClient.get("\(Constants.Twilio.faxUrl)/Faxes/\(twilioFax.sid)", headers: headers).do { response in
                guard response.http.status.isValid else {
                    return promise.fail(error: ServerAbort(response.http.status, reason: "Twilio reponse error"))
                }
                do {
                    let twilioFax = try response.content.syncDecode(TwilioFax.self)
                    document.update(withFax: twilioFax)
                    
                    try Fax.collection.update("_id" == document.objectId, to: document)
                    document.sendAlert(request, objectId: objectId, to: document["senderEmail"] as? String, subject: "Fax Status Update", alertType: .faxStatus)
                    
                    return promise.succeed(result: ServerResponse.response(request.statusResponse(status: .ok)))
                } catch let error {
                    Logger.error("Fax Status Update Error: \(error)")
                    return promise.fail(error: error)
                }
            }.catch { error in
                Logger.error("Fax Status Update Error: \(error)")
                return promise.fail(error: error)
            }
        }
    }
    
    // MARK: POST receive
    func postReceive(_ request: Request) throws -> Future<ServerResponse> {
        return request.globalAsync { promise in
            let twilioFax = try request.content.syncDecode(TwilioIncommingFax.self)
            guard let account = try Account.collection.findOne("accountSid" == twilioFax.accountSid) else {
                throw ServerAbort(.notFound, reason: "Account not found")
            }
            let authToken = try account.extract("authToken") as String
            let token = try String.token()
            
            var document: Document = [
                "sid": twilioFax.sid,
                "accountSid": twilioFax.accountSid,
                "from": twilioFax.from,
                "to": twilioFax.to,
                "remoteStationId": twilioFax.remoteStationId,
                "status": twilioFax.status,
                "direction": "inbound",
                "apiVersion": twilioFax.apiVersion,
                "pages": twilioFax.pages,
                "mediaUrl": twilioFax.mediaUrl,
                "errorCode": twilioFax.errorCode,
                "errorMessage": twilioFax.errorMessage,
                "token": token
            ]
            
            let requestClient = try request.make(Client.self)
            let headers = HTTPHeaders([
                ("Authorization", "Basic \(try String.twilioAuthString(twilioFax.accountSid, authToken: authToken))"),
                ("Accept", "application/json")
            ])
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
            requestClient.get("\(Constants.Twilio.faxUrl)/Faxes/\(twilioFax.sid)", headers: headers).do { response in
                guard response.http.status.isValid else {
                    return promise.fail(error: ServerAbort(response.http.status, reason: "Twilio reponse error"))
                }
                do {
                    let twilioFax = try response.content.syncDecode(TwilioFax.self)
                    
                    guard let mediaUrl = twilioFax.mediaUrl else {
                        throw ServerAbort(.badRequest, reason: "Media URL Required")
                    }
                    
                    getMedia(mediaUrl: mediaUrl) { mediaResponse in
                        do {
                            guard mediaResponse.http.status == .ok, let data = mediaResponse.http.body.data else {
                                throw ServerAbort(.notFound, reason: "Error getting fax media")
                            }
                            document.update(withFax: twilioFax)
                            guard let objectId = try Fax.collection.insert(document) as? ObjectId else {
                                throw ServerAbort(.notFound, reason: "Error creating fax")
                            }
                            document.sendAlert(request, objectId: objectId, to: account["notificationEmail"] as? String ?? Admin.settings.notificationEmail, subject: "Fax Received", alertType: .faxReceived)
                            
                            let fileDocument: Document = [
                                "faxObjectId": objectId,
                                "token": token,
                                "dateCreated": Date(),
                                "data": data
                            ]
                            
                            try FaxFile.collection.insert(fileDocument)
                            
                            return promise.succeed(result: ServerResponse.response(request.statusResponse(status: .ok)))
                        } catch let error {
                            Logger.error("Fax Receive Error: \(error)")
                            return promise.fail(error: error)
                        }
                    }
                } catch let error {
                    Logger.error("Fax Receive Error: \(error)")
                    return promise.fail(error: error)
                }
            }.catch { error in
                Logger.error("Fax Receive Error: \(error)")
                return promise.fail(error: error)
            }
        }
    }
}
