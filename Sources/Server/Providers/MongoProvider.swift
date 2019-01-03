//
//  MongoProvider.swift
//  Server
//
//  Created by BluDesign, LLC on 3/25/17.
//

import Foundation
import Vapor
import MongoKitten

final class MongoProvider: Provider {
    
    // MARK: - Enums
    
    enum Error: Swift.Error {
        case config(String)
    }
    
    // MARK: - Parameters
    
    static let shared = MongoProvider()
    
    var database: MongoKitten.Database
    var server: MongoKitten.Server
    
    // MARK: - Life Cycle
    
    init() {
        do {
            Logger.debug("Starting Mongo Provider")
            let databaseName = Environment.get("MONGO_DATABASE") ?? "vapor"
            let host = Environment.get("MONGO_HOST") ?? "localhost"
            let port = Environment.get("MONGO_PORT")?.intValue ?? 27017
            let credentials: MongoCredentials?
            if let username = Environment.get("MONGO_USERNAME"), let password = Environment.get("MONGO_PASSWORD") {
                credentials = MongoCredentials(username: username, password: password)
            } else {
                credentials = nil
            }
            let clientSettings = ClientSettings(host: MongoHost(hostname:host, port: UInt16(port)), sslSettings: nil, credentials: credentials, maxConnectionsPerServer: 100, defaultTimeout: TimeInterval(1800), applicationName: nil)
            server = try Server(clientSettings)
//            server.logger = PrintLogger()
//            server.whenExplaining = { explaination in
//                Logger.verbose("Explained: \(explaination)")
//            }
            database = server[databaseName]
        } catch let error {
            Logger.error("Mongo Provider Start Error: \(error)")
            exit(1)
        }
    }
    
    // MARK: - Methods
    
    func register(_ services: inout Services) throws {
        
    }
    
    func willBoot(_ container: Container) throws -> Future<Void> {
        Logger.debug("Mongo Provider: Will Boot Connected: \(server.isConnected)")
        return .done(on: container)
    }
    
    func didBoot(_ container: Container) throws -> EventLoopFuture<Void> {
        try createIndexes()
        Logger.debug("Mongo Provider: Did Boot Connected: \(server.isConnected)")
        return .done(on: container)
    }
    
    func createIndexes() throws {
        Logger.debug("Mongo Provider: Creating Indexes")
        let collections = try database.listCollections()
        var collectionNames: Set<String> = []
        for collection in collections {
            collectionNames.insert(collection.name)
        }
        if collectionNames.contains(AuthenticityToken.collectionName) == false {
            try database.createCollection(named: AuthenticityToken.collectionName)
        }
        if collectionNames.contains(AuthorizationCode.collectionName) == false {
            try database.createCollection(named: AuthorizationCode.collectionName)
        }
        if collectionNames.contains(PasswordReset.collectionName) == false {
            try database.createCollection(named: PasswordReset.collectionName)
        }
        if collectionNames.contains(AccessToken.collectionName) == false {
            try database.createCollection(named: AccessToken.collectionName)
        }
        if collectionNames.contains(Fax.collectionName) == false {
            try database.createCollection(named: Fax.collectionName)
        }
        if collectionNames.contains(Message.collectionName) == false {
            try database.createCollection(named: Message.collectionName)
        }
        if collectionNames.contains(Contact.collectionName) == false {
            try database.createCollection(named: Contact.collectionName)
        }
        if AuthenticityToken.collection.containsIndex("ttl") == false {
            try AuthenticityToken.collection.createIndex(named: "ttl", withParameters: .sort(field: "createdAt", order: .ascending), .expire(afterSeconds: 600), .buildInBackground)
        }
        if AuthorizationCode.collection.containsIndex("ttl") == false {
            try AuthorizationCode.collection.createIndex(named: "ttl", withParameters: .sort(field: "createdAt", order: .ascending), .expire(afterSeconds: 600), .buildInBackground)
        }
        if PasswordReset.collection.containsIndex("ttl") == false {
            try PasswordReset.collection.createIndex(named: "ttl", withParameters: .sort(field: "createdAt", order: .ascending), .expire(afterSeconds: 3600), .buildInBackground)
        }
        if AccessToken.collection.containsIndex("ttl") == false {
            try AccessToken.collection.createIndex(named: "ttl", withParameters: .sort(field: "endOfLife", order: .ascending), .expire(afterSeconds: 0), .buildInBackground)
        }
        if Fax.collection.containsIndex("dateCreated") == false {
            try Fax.collection.createIndex(named: "dateCreated", withParameters: .sort(field: "dateCreated", order: .descending), .buildInBackground)
        }
        if Message.collection.containsIndex("dateCreated") == false {
            try Message.collection.createIndex(named: "dateCreated", withParameters: .sort(field: "dateCreated", order: .descending), .buildInBackground)
        }
        if Contact.collection.containsIndex("firstName") == false {
            try Contact.collection.createIndex(named: "firstName", withParameters: .sort(field: "firstName", order: .ascending), .buildInBackground)
        }
        if Admin.settings.databaseVersion == 1 {
            try Message.collection.update(to: ["$rename": ["numMedia": "mediaCount"]], multiple: true)
            Admin.settings.databaseVersion = 2
            try Admin.settings.save()
        }
        Logger.debug("Mongo Provider: Creating Indexes Complete")
    }
}

extension MongoKitten.Collection {
    func containsIndex(_ name: String) -> Bool {
        do {
            let indexes = try listIndexes()
            for index in indexes {
                guard let indexName = index["name"] as? String else { continue }
                if name == indexName {
                    return true
                }
            }
        } catch {
            do {
                try dropIndex(named: name)
            } catch {}
            return false
        }
        return false
    }
}
