//
//  Client+Routes.swift
//  Server
//
//  Created by BluDesign, LLC on 4/2/17.
//

import Foundation
import Vapor
import MongoKitten
import BCrypt

extension Client {
    
    // MARK: - Methods
    
    static func routes(_ drop: Droplet, _ group: RouteBuilder) {
        let protected = group.grouped([AuthenticationMiddleware.shared])
        
        func getClients(request: Request, client: (clientId: String, clientSecret: String, resetSecret: Bool)? = nil) throws -> ResponseRepresentable {
            let skip = request.data["skip"]?.int ?? 0
            let limit = min(100, request.data["limit"]?.int ?? 100)
            let documents = try Client.collection.find(sortedBy: ["name": .ascending], projecting: [
                "secret": false
            ], skipping: skip, limitedTo: limit, withBatchSize: limit)
            if request.jsonResponse {
                return try documents.makeResponse()
            } else {
                var tableData: String = ""
                for document in documents {
                    let id = try document.extractObjectId()
                    let name = try document.extractString("name")
                    let website = try document.extractString("website")
                    let redirectUri = try document.extractString("redirectUri")
                    let string = "<tr onclick=\"location.href='/client/\(id.hexString)'\"><td>\(name)</td><td>\(id.hexString)</td><td>\(website)</td><td>\(redirectUri)</td></tr>"
                    tableData.append(string)
                }
                if let client = client {
                    return try drop.view.make("clients", [
                        "clientId": client.clientId,
                        "clientSecret": client.clientSecret,
                        "showSecret": true,
                        "resetSecret": client.resetSecret,
                        "tableData": tableData
                    ])
                }
                return try drop.view.make("clients", ["tableData": tableData])
            }
        }
        
        // MARK: Get Clients
        protected.get { request in
            return try getClients(request: request)
        }
        
        // MARK: Create Client
        protected.post { request in
            let name = try request.data.extract("name") as String
            let website = try request.data.extract("website") as String
            let redirectUri = try request.data.extract("redirectUri") as String
            
            let secret = try String.tokenEncoded()
            let secretHash = try BCrypt.Hash.make(message: secret, with: Salt()).makeString()
            let document: Document = [
                "name": name,
                "website": website,
                "redirectUri": redirectUri,
                "secret": secretHash
            ]
            guard let clientId = try Client.collection.insert(document) as? ObjectId else {
                throw ServerAbort(.notFound, reason: "Error creating client")
            }
            
            if request.jsonResponse {
                return try JSON(node: [
                    "clientId": clientId.hexString,
                    "clientSecret": secret
                ])
            } else {
                return try getClients(request: request, client: (clientId: clientId.hexString, clientSecret: secret, resetSecret: false))
            }
        }
        
        // MARK: Get Client
        protected.get(":objectId") { request in
            let objectId = try request.parameters.extract("objectId") as ObjectId
            guard let document = try Client.collection.findOne("_id" == objectId, projecting: [
                "secret": false
            ]) else {
                throw ServerAbort(.notFound, reason: "Client not found")
            }
            
            if request.jsonResponse {
                return try document.makeResponse()
            } else {
                return try drop.view.make("client", [
                    "name": try document.extract("name") as String,
                    "website": try document.extract("website") as String,
                    "redirectUri": try document.extract("redirectUri") as String,
                    "clientId": objectId.hexString
                ])
            }
        }
        
        // MARK: Update Client
        protected.post(":objectId") { request in
            let objectId = try request.parameters.extract("objectId") as ObjectId
            guard var document = try Client.collection.findOne("_id" == objectId) else {
                throw ServerAbort(.notFound, reason: "Client not found")
            }
            
            if request.data["action"]?.string == "delete" {
                try Client.collection.remove("_id" == objectId)
                if request.jsonResponse {
                    return Response(jsonStatus: .ok)
                }
                return Response(redirect: "/client")
            }
            
            if let name = try? request.data.extract("name") as String {
                document["name"] = name
            }
            if let website = try? request.data.extract("website") as String {
                document["website"] = website
            }
            if let redirectUri = try? request.data.extract("redirectUri") as String {
                document["redirectUri"] = redirectUri
            }
            
            guard request.data["action"]?.string != "resetSecret" else {
                let objectId = try document.extract("_id") as ObjectId
                let secret = try String.tokenEncoded()
                let secretHash = try BCrypt.Hash.make(message: secret, with: Salt()).makeString()
                document["secret"] = secretHash
                try Client.collection.update("_id" == objectId, to: document, upserting: true)
                if request.jsonResponse {
                    return try JSON(node: [
                        "clientId": objectId.hexString,
                        "clientSecret": secret
                    ])
                } else {
                    return try getClients(request: request, client: (clientId: objectId.hexString, clientSecret: secret, resetSecret: true))
                }
            }
            try Client.collection.update("_id" == objectId, to: document, upserting: true)
            if request.jsonResponse {
                return Response(jsonStatus: .ok)
            }
            return Response(redirect: "/client")
        }
    }
}
