//
//  Client+Routes.swift
//  Server
//
//  Created by BluDesign, LLC on 4/2/17.
//

import Foundation
import Vapor
import MongoKitten
import Crypto

struct FaxClientRouter {
    
    init(router: Router) {
        let adminRouter = router.grouped(AdminAuthenticationMiddleware.self)
        
        adminRouter.get(use: get)
        adminRouter.post(use: post)
        adminRouter.get(ObjectId.parameter, use: getClient)
        adminRouter.post(ObjectId.parameter, use: postClient)
    }
    
    // MARK: GET
    func get(_ request: Request) throws -> Future<ServerResponse> {
        return try FaxClientRouter.get(request, client: nil)
    }
    
    // MARK: GET with FaxClient Info
    static func get(_ request: Request, client: (clientId: String, clientSecret: String, resetSecret: Bool)?) throws -> Future<ServerResponse> {
        return request.globalAsync { promise in
            let pageInfo = request.pageInfo
            
            let clients = try FaxClient.collection.find(sortedBy: ["name": .ascending], projecting: [
                "secret": false
                ], skipping: pageInfo.skip, limitedTo: pageInfo.limit, withBatchSize: pageInfo.limit)
            if request.jsonResponse {
                return promise.submit(try clients.makeResponse(request))
            } else {
                var tableData: String = ""
                for client in clients {
                    let clientId = try client.extractObjectId()
                    let name = try client.extractString("name")
                    let website = try client.extractString("website")
                    let redirectUri = try client.extractString("redirectUri")
                    let string = "<tr onclick=\"location.href='/client/\(clientId.hexString)'\"><td>\(name)</td><td>\(clientId.hexString)</td><td>\(website)</td><td>\(redirectUri)</td></tr>"
                    tableData.append(string)
                }
                var contextDictionary: [String: TemplateData] = [
                    "tableData": .string(tableData),
                    "admin": .bool(try request.authentication().permission.isAdmin),
                    "contactsEnabled": .bool(Admin.settings.googleClientId != nil && Admin.settings.googleClientSecret != nil)
                ]
                if let client = client {
                    contextDictionary["clientId"] = .string(client.clientId)
                    contextDictionary["clientSecret"] = .string(client.clientSecret)
                    contextDictionary["resetSecret"] = .bool(client.resetSecret)
                    contextDictionary["showSecret"] = .bool(true)
                }
                let context = TemplateData.dictionary(contextDictionary)
                return promise.submit(try request.renderEncoded("clients", context))
            }
        }
    }
    
    // MARK: POST
    func post(_ request: Request) throws -> Future<ServerResponse> {
        return request.globalAsync { promise in
            struct FormData: Decodable {
                let name: String
                let website: String
                let redirectUri: String
            }
            let formData = try request.content.syncDecode(FormData.self)
            
            let secret = try String.tokenEncoded()
            let secretHash = try BCryptDigest().hash(secret)
            let client: Document = [
                "name": formData.name,
                "website": formData.website,
                "redirectUri": formData.redirectUri,
                "secret": secretHash
            ]
            guard let clientId = try FaxClient.collection.insert(client) as? ObjectId else {
                throw ServerAbort(.notFound, reason: "Error creating client")
            }
            if request.jsonResponse {
                let json: [String: Codable] = [
                    "clientId": clientId.hexString,
                    "clientSecret": secret
                ]
                return promise.submit(try request.jsonEncoded(json: json))
            } else {
                return promise.submit(try FaxClientRouter.get(request, client: (clientId: clientId.hexString, clientSecret: secret, resetSecret: false)))
            }
        }
    }
    
    // MARK: GET :clientId
    func getClient(_ request: Request) throws -> Future<ServerResponse> {
        return request.globalAsync { promise in
            let clientId = try request.parameters.next(ObjectId.self)
            guard let client = try FaxClient.collection.findOne("_id" == clientId, projecting: [
                "secret": false
            ]) else {
                throw ServerAbort(.notFound, reason: "Client not found")
            }
            if request.jsonResponse {
                return promise.submit(try client.makeResponse(request))
            } else {
                let context = TemplateData.dictionary([
                    "name": .string(try client.extract("name") as String),
                    "website": .string(try client.extract("website") as String),
                    "redirectUri": .string(try client.extract("redirectUri") as String),
                    "clientId": .string(clientId.hexString),
                    "admin": .bool(try request.authentication().permission.isAdmin),
                    "contactsEnabled": .bool(Admin.settings.googleClientId != nil && Admin.settings.googleClientSecret != nil)
                ])
                return promise.submit(try request.renderEncoded("client", context))
            }
        }
    }
    
    // MARK: POST :clientId
    func postClient(_ request: Request) throws -> Future<ServerResponse> {
        return request.globalAsync { promise in
            struct FormData: Decodable {
                let name: String?
                let website: String?
                let redirectUri: String?
                let action: String?
            }
            let clientId = try request.parameters.next(ObjectId.self)
            guard var client = try FaxClient.collection.findOne("_id" == clientId) else {
                throw ServerAbort(.notFound, reason: "Client not found")
            }
            let formData = try request.content.syncDecode(FormData.self)
            if formData.action == "delete" {
                try FaxClient.collection.remove("_id" == clientId)
                return promise.succeed(result: request.serverStatusRedirect(status: .ok, to: "/client"))
            }
            if let name = formData.name {
                client["name"] = name
            }
            if let website = formData.website {
                client["website"] = website
            }
            if let redirectUri = formData.redirectUri {
                client["redirectUri"] = redirectUri
            }
            
            guard formData.action != "resetSecret" else {
                let secret = try String.tokenEncoded()
                let secretHash = try BCryptDigest().hash(secret)
                client["secret"] = secretHash
                try FaxClient.collection.update("_id" == clientId, to: client, upserting: true)
                if request.jsonResponse {
                    let json: [String: Codable] = [
                        "clientId": clientId.hexString,
                        "clientSecret": secret
                    ]
                    return promise.submit(try request.jsonEncoded(json: json))
                } else {
                    return promise.submit(try FaxClientRouter.get(request, client: (clientId: clientId.hexString, clientSecret: secret, resetSecret: false)))
                }
            }
            try FaxClient.collection.update("_id" == clientId, to: client, upserting: true)
            return promise.succeed(result: request.serverStatusRedirect(status: .ok, to: "/client"))
        }
    }
}
