//
//  Contact+Routes.swift
//  Server
//
//  Created by BluDesign, LLC on 3/9/18.
//

import Foundation
import Vapor
import MongoKitten
import AEXML

struct ContactRouter {
    
    init(router: Router) {
        let protectedRouter = router.grouped(AuthenticationMiddleware.self)
        let basicAuthenticationRouter = router.grouped(BasicAuthenticationMiddleware.self)
        
        protectedRouter.get("code", use: getCode)
        protectedRouter.post(use: post)
        protectedRouter.get(use: get)
        basicAuthenticationRouter.get("phonebook.xml", use: getPhoneBookXml)
    }
    
    // MARK: GET code
    func getCode(_ request: Request) throws -> Future<ServerResponse> {
        return request.globalAsync { promise in
            guard let domain = Admin.settings.domain else {
                throw ServerAbort(.notFound, reason: "No host URL set in settings")
            }
            guard let clientId = Admin.settings.googleClientId?.urlQueryPercentEncodedPlus else {
                throw ServerAbort(.notFound, reason: "No Google Client ID set in settings")
            }
            guard let clientSecret = Admin.settings.googleClientSecret?.urlQueryPercentEncodedPlus else {
                throw ServerAbort(.notFound, reason: "No Google API secret set in settings")
            }
            let authentication = try request.authentication()
            let code = (try request.query.get(at: "code") as String)
            let redirectUri = "\(domain)/contact/code"
            
            let requestClient = try request.make(Client.self)
            let headers = HTTPHeaders([
                ("Content-Type", "application/x-www-form-urlencoded"),
                ("Accept", "application/json")
            ])
            let content: [String: String] = [
                "code": code,
                "client_id": clientId,
                "client_secret": clientSecret,
                "redirect_uri": redirectUri,
                "grant_type": "authorization_code"
            ]
            requestClient.post("https://www.googleapis.com/oauth2/v4/token", headers: headers, beforeSend: { request in
                try request.content.encode(content, as: .urlEncodedForm)
            }).do { response in
                do {
                    guard response.http.status.isValid else {
                        throw ServerAbort(response.http.status, reason: "Google reponse error")
                    }
                    struct AccessToken: Decodable {
                        let accessToken: String
                        let refreshToken: String
                        let expiresIn: Double
                        
                        private enum CodingKeys : String, CodingKey {
                            case accessToken = "access_token"
                            case refreshToken = "refresh_token"
                            case expiresIn = "expires_in"
                        }
                    }
                    let accessToken = try response.content.syncDecode(AccessToken.self)
                    let expireDate = Date(timeIntervalSinceNow: accessToken.expiresIn)
                    
                    let update: Document = [
                        "googleAccessToken": accessToken.accessToken,
                        "googleRefreshToken": accessToken.refreshToken,
                        "googleExpires": expireDate
                    ]
                    try User.collection.update("_id" == authentication.userId, to: ["$set": update], upserting: false)
                    
                    return promise.succeed(result: request.serverStatusRedirect(status: .ok, to: "/contact"))
                } catch let error {
                    return promise.fail(error: error)
                }
            }.catch { error in
                return promise.fail(error: error)
            }
        }
    }
    
    // MARK: GET
    func get(_ request: Request) throws -> Future<ServerResponse> {
        return request.globalAsync { promise in
            let authentication = try request.authentication()
            
            guard Admin.settings.googleClientId != nil && Admin.settings.googleClientSecret != nil else {
                throw ServerAbort(.notImplemented, reason: "Google contacts not setup in admin settings")
            }
            
            guard let user = try User.collection.findOne("_id" == authentication.userId, projecting: [
                "googleAccessToken": true
            ]) else {
                throw ServerAbort(.notFound, reason: "User not found")
            }
            let pageInfo = request.pageInfo
            let documents = try Contact.collection.find("userId" == authentication.userId, sortedBy: ["firstName": .ascending], skipping: pageInfo.skip, limitedTo: pageInfo.limit, withBatchSize: pageInfo.limit)
            if request.jsonResponse {
                return promise.submit(try documents.makeResponse(request))
            } else {
                let link = "/contact?"
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
                
                var tableData: String = ""
                for document in documents {
                    guard let contact = Contact(document: document) else { continue }
                    let phoneNumbers = contact.mainPhoneNumbers
                    let string = "<tr><td>\(contact.firstName ?? "")</td><td>\(contact.lastName ?? "")</td><td>\(contact.organization ?? "")</td><td>\(contact.groupName ?? "")</td><td>\(phoneNumbers.home?.number ?? "")</td><td>\(phoneNumbers.work?.number ?? "")</td><td>\(phoneNumbers.cell?.number ?? "")</td></tr>"
                    tableData.append(string)
                }
                let context = TemplateData.dictionary([
                    "tableData": .string(tableData),
                    "accountConnected": .bool(user["googleAccessToken"] as? String != nil),
                    "pageData": .string(pageData),
                    "page": .int(pageInfo.page),
                    "nextPage": .string((pageInfo.page + 1 > pages ? "#" : "\(link)page=\(pageInfo.page + 1)")),
                    "prevPage": .string((pageInfo.page - 1 <= 0 ? "#" : "\(link)page=\(pageInfo.page - 1)")),
                    "admin": .bool(authentication.permission.isAdmin),
                    "contactsEnabled": .bool(Admin.settings.googleClientId != nil && Admin.settings.googleClientSecret != nil)
                ])
                return promise.submit(try request.renderEncoded("contacts", context))
            }
        }
    }
    
    // MARK: POST
    func post(_ request: Request) throws -> Future<ServerResponse> {
        return request.globalAsync { promise in
            let authentication = try request.authentication()
            
            let action = try request.content.syncGet(String.self, at: "action")
            if action == "connect" {
                guard let domain = Admin.settings.domain else {
                    throw ServerAbort(.notFound, reason: "No host URL set in settings")
                }
                let scope = "https://www.googleapis.com/auth/contacts.readonly".urlQueryPercentEncodedPlus
                let redirectUri = "\(domain)/contact/code".urlQueryPercentEncodedPlus
                guard let clientId = Admin.settings.googleClientId?.urlQueryPercentEncodedPlus else {
                    throw ServerAbort(.notFound, reason: "No Google Client ID set in settings")
                }
                let url = "https://accounts.google.com/o/oauth2/v2/auth?scope=\(scope)&access_type=offline&include_granted_scopes=true&redirect_uri=\(redirectUri)&response_type=code&client_id=\(clientId)"
                return promise.succeed(result: request.serverStatusRedirect(status: .ok, to: url))
            } else if action == "disconnect" {
                let count = try User.collection.update("_id" == authentication.userId, to: ["$unset": ["googleAccessToken": 1, "googleRefreshToken": 1, "googleExpires": 1]], upserting: false)
                guard count > 0 else {
                    throw ServerAbort(.internalServerError, reason: "Could not disconnect Google")
                }
                return promise.succeed(result: request.serverStatusRedirect(status: .ok, to: "/contact"))
            } else if action == "sync" {
                if let result = try? self.getContacts(userId: authentication.userId) {
                    try self.syncContacts(userId: authentication.userId, contacts: result.contacts, groups: result.groups)
                }
                return promise.succeed(result: request.serverStatusRedirect(status: .ok, to: "/contact"))
            } else {
                throw ServerAbort(.internalServerError, reason: "Invalid action")
            }
        }
    }

    // MARK: GET phoneBook.xml
    func getPhoneBookXml(_ request: Request) throws -> Future<ServerResponse> {
        return request.globalAsync { promise in
            let authentication = try request.authentication()
            let result = try self.getContacts(userId: authentication.userId)
            let xml = AEXMLDocument()
            let addressBook = xml.addChild(name: "AddressBook")
            
            var groupXml = addressBook.addChild(name: "pbgroup")
            _ = groupXml.addChild(name: "id", value: "1")
            _ = groupXml.addChild(name: "name", value: "Blacklist")
            groupXml = addressBook.addChild(name: "pbgroup")
            _ = groupXml.addChild(name: "id", value: "2")
            _ = groupXml.addChild(name: "name", value: "Whitelist")
            
            var currentId = 3
            var groupIds: [String: (id: Int, name: String)] = [:]
            for (groupId, groupName) in result.groups {
                let groupXml = addressBook.addChild(name: "pbgroup")
                _ = groupXml.addChild(name: "id", value: "\(currentId)")
                _ = groupXml.addChild(name: "name", value: groupName)
                groupIds[groupId] = (id: currentId, name: groupName)
                currentId += 1
            }
            
            for contact in result.contacts {
                let contactXml = addressBook.addChild(name: "Contact")
                guard let firstName = contact.firstName else { continue }
                _ = contactXml.addChild(name: "FirstName", value: firstName)
                if let lastName = contact.lastName {
                    _ = contactXml.addChild(name: "LastName", value: lastName)
                }
                if let company = contact.organization {
                    _ = contactXml.addChild(name: "Company", value: company)
                }
                _ = contactXml.addChild(name: "Primary", value: "0")
                
                if let groupId = contact.groupId, let group = groupIds[groupId] {
                    _ = contactXml.addChild(name: "Group", value: "\(group.id)")
                }
                
                let phoneNumbers = contact.mainPhoneNumbers
                if let phoneNumber = phoneNumbers.home {
                    let phone = contactXml.addChild(name: "Phone", attributes: ["type": "Home"])
                    _ = phone.addChild(name: "phonenumber", value: phoneNumber.number)
                    _ = phone.addChild(name: "accountindex", value: "0")
                }
                if let phoneNumber = phoneNumbers.work {
                    let phone = contactXml.addChild(name: "Phone", attributes: ["type": "Work"])
                    _ = phone.addChild(name: "phonenumber", value: phoneNumber.number)
                    _ = phone.addChild(name: "accountindex", value: "0")
                }
                if let phoneNumber = phoneNumbers.cell {
                    let phone = contactXml.addChild(name: "Phone", attributes: ["type": "Cell"])
                    _ = phone.addChild(name: "phonenumber", value: phoneNumber.number)
                    _ = phone.addChild(name: "accountindex", value: "0")
                }
            }
            
            let response = Response(using: request.sharedContainer)
            response.http.headers.replaceOrAdd(name: .contentType, value:"application/xml; charset=utf-8")
            response.http.body = HTTPBody(string: xml.xml)
            response.http.status = .ok
            return promise.succeed(result: ServerResponse.response(response))
        }
    }
    
    func syncContacts(userId: ObjectId, contacts: [Contact], groups: [String: String]) throws {
        var contactDocuments: [Document] = []
        for contact in contacts {
            let groupName: String?
            if let groupId = contact.groupId {
                groupName = groups[groupId]
            } else {
                groupName = nil
            }
            contactDocuments.append(contact.document(userId: userId, groupName: groupName))
        }
        
        try Contact.collection.remove("userId" == userId)
        try Contact.collection.insert(contentsOf: contactDocuments)
    }
    
    func getGroups(userId: ObjectId) throws -> [String: (name: String, used: Int)] {
        guard let user = try User.collection.findOne("_id" == userId, projecting: [
            "googleAccessToken": true
        ]) else {
            throw ServerAbort(.notFound, reason: "User not found")
        }
        guard let accessToken = user["googleAccessToken"] as? String else {
            throw ServerAbort(.notFound, reason: "Missing Google access token")
        }
        
        let groupsUrl = "https://people.googleapis.com/v1/contactGroups?pageSize=10"
        
        
        let requestClient = try MainApplication.shared.application.make(Client.self)
        let headers = HTTPHeaders([
            ("Authorization", "Bearer \(accessToken)"),
            ("Accept", "application/json")
        ])
        var response = try requestClient.get(groupsUrl, headers: headers).wait()
        if response.http.status == .unauthorized {
            let accessToken = try renewAccessToken(userId: userId)
            let headers = HTTPHeaders([
                ("Authorization", "Bearer \(accessToken)"),
                ("Accept", "application/json")
            ])
            response = try requestClient.get(groupsUrl, headers: headers).wait()
        }
        
        guard response.http.status == .ok else {
            if response.http.status == .unauthorized {
                try User.collection.update("_id" == userId, to: ["$unset": ["googleAccessToken": 1, "googleRefreshToken": 1, "googleExpires": 1]], upserting: false)
            }
            throw ServerAbort(.notFound, reason: "Error getting groups")
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        let contactGroups = try response.content.decode(json: ContactGroups.self, using: .custom(dates: .formatted(dateFormatter))).wait()
        
        var groupNames: [String: (name: String, used: Int)] = [:]
        
        for contactGroup in contactGroups.contactGroups {
            var resourceNames = contactGroup.resourceName.components(separatedBy: "/")
            guard resourceNames.count > 1 else { continue }
            resourceNames.removeFirst()
            let groupId = resourceNames.joined(separator: "/")
            groupNames[groupId] = (name: contactGroup.formattedName, used: 0)
        }
        
        groupNames.removeValue(forKey: "all")
        groupNames.removeValue(forKey: "myContacts")
        groupNames.removeValue(forKey: "chatBuddies")
        groupNames.removeValue(forKey: "blocked")
        
        return groupNames
    }
    
    func getContacts(userId: ObjectId) throws -> (contacts: [Contact], groups: [String: String]) {
        guard let user = try User.collection.findOne("_id" == userId, projecting: [
            "googleAccessToken": true
        ]) else {
            throw ServerAbort(.notFound, reason: "User not found")
        }
        guard let accessToken = user["googleAccessToken"] as? String else {
            throw ServerAbort(.notFound, reason: "Missing Google access token")
        }
        
        var groupNames = try getGroups(userId: userId)
        
        let url = "https://people.googleapis.com/v1/people/me/connections?pageSize=2000&personFields=names,phoneNumbers,organizations,memberships"
        
        let requestClient = try MainApplication.shared.application.make(Client.self)
        let headers = HTTPHeaders([
            ("Authorization", "Bearer \(accessToken)"),
            ("Accept", "application/json")
        ])
        var response = try requestClient.get(url, headers: headers).wait()
        if response.http.status == .unauthorized {
            let accessToken = try renewAccessToken(userId: userId)
            let headers = HTTPHeaders([
                ("Authorization", "Bearer \(accessToken)"),
                ("Accept", "application/json")
            ])
            response = try requestClient.get(url, headers: headers).wait()
        }
        
        guard response.http.status == .ok else {
            if response.http.status == .unauthorized {
                try User.collection.update("_id" == userId, to: ["$unset": ["googleAccessToken": 1, "googleRefreshToken": 1, "googleExpires": 1]], upserting: false)
            }
            throw ServerAbort(.notFound, reason: "Error getting groups")
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        let connections = try response.content.decode(json: Connections.self, using: .custom(dates: .formatted(dateFormatter))).wait()
        
        var contacts: [Contact] = []
        for connection in connections.connections {
            guard let phoneNumbers = connection.phoneNumbers else { continue }
            var contact = Contact(objectId: connection.resourceName.replacingOccurrences(of: "people/", with: ""))
            if let name = connection.names?.first {
                if let firstName = name.givenName, let lastName = name.familyName {
                    contact.firstName = firstName
                    contact.lastName = lastName
                } else {
                    contact.firstName = name.displayName
                }
                contact.organization = connection.organizations?.first?.name
            } else if let name = connection.organizations?.first?.name {
                contact.firstName = name
            } else {
                continue
            }
            for phoneNumber in phoneNumbers {
                guard let number = phoneNumber.canonicalForm?.replacingOccurrences(of: "+1", with: "") else { continue }
                let primary = phoneNumber.metadata.primary ?? false
                let type = phoneNumber.type ?? "other"
                let phoneNumber = Contact.PhoneNumber(type: type, number: number, primary: primary)
                contact.phoneNumbers[phoneNumber.type] = phoneNumber
            }
            guard contact.phoneNumbers.count > 0 else { continue }
            if let memberships = connection.memberships {
                for membership in memberships {
                    let groupId = membership.contactGroupMembership.contactGroupId
                    guard let group = groupNames[groupId] else { continue }
                    contact.groupId = groupId
                    groupNames[groupId] = (name: group.name, used: group.used + 1)
                }
            }
            contacts.append(contact)
        }

        var finalGroups: [String: String] = [:]
        for (groupId, group) in groupNames where group.used > 0 {
            finalGroups[groupId] = group.name
        }

        return (contacts: contacts, groups: finalGroups)
    }
    
    func renewAccessToken(userId: ObjectId) throws -> String {
        guard let clientId = Admin.settings.googleClientId?.urlQueryPercentEncodedPlus else {
            throw ServerAbort(.notFound, reason: "No Google Client ID set in settings")
        }
        guard let clientSecret = Admin.settings.googleClientSecret?.urlQueryPercentEncodedPlus else {
            throw ServerAbort(.notFound, reason: "No Google API secret set in settings")
        }
        
        guard let user = try User.collection.findOne("_id" == userId, projecting: [
            "googleRefreshToken": true
        ]) else {
            throw ServerAbort(.notFound, reason: "User not found")
        }
        guard let refreshToken = user["googleRefreshToken"] as? String else {
            throw ServerAbort(.notFound, reason: "Missing Google refresh token")
        }
        
        let requestClient = try MainApplication.shared.application.make(Client.self)
        let headers = HTTPHeaders([
            ("Content-Type", "application/x-www-form-urlencoded"),
            ("Accept", "application/json")
        ])
        let content: [String: String] = [
            "refresh_token": refreshToken,
            "client_id": clientId,
            "client_secret": clientSecret,
            "grant_type": "refresh_token"
        ]
        let response = try requestClient.post("https://www.googleapis.com/oauth2/v4/token", headers: headers, beforeSend: { request in
            try request.content.encode(content, as: .urlEncodedForm)
        }).wait()
        
        guard response.http.status.isValid else {
            throw ServerAbort(response.http.status, reason: "Google reponse error")
        }
        struct AccessToken: Decodable {
            let accessToken: String
            let expiresIn: Double
            
            private enum CodingKeys : String, CodingKey {
                case accessToken = "access_token"
                case expiresIn = "expires_in"
            }
        }
        let accessToken = try response.content.syncDecode(AccessToken.self)
        let expireDate = Date(timeIntervalSinceNow: accessToken.expiresIn)
        
        let update: Document = [
            "googleAccessToken": accessToken.accessToken,
            "googleExpires": expireDate
        ]
        try User.collection.update("_id" == userId, to: ["$set": update], upserting: false)
        
        return accessToken.accessToken
    }
}
