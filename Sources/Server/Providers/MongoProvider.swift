//
//  MongoProvider.swift
//  Server
//
//  Created by BluDesign, LLC on 3/25/17.
//

import Foundation
import Vapor
import MongoKitten

final class MongoProvider: Vapor.Provider {
    
    // MARK: - Enums
    
    enum Error: Swift.Error {
        case config(String)
    }
    
    // MARK: - Parameters
    
    static let repositoryName = "Mongo"
    
    var database: MongoKitten.Database
    var server: MongoKitten.Server
    
    // MARK: - Life Cycle
    
    init(config: Config) throws {
        Logger.debug("Starting Mongo Provider")
        guard let mongo = config["mongo"]?.object else {
            throw Error.config("No mongo.json config file.")
        }
        
        guard let databaseName = mongo["database"]?.string else {
            throw Error.config("No 'database' key in mongo.json config file.")
        }
        
        let host = mongo["host"]?.string ?? "localhost"
        let port = mongo["port"]?.int ?? 27017
        if let user = mongo["user"]?.string?.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed), user.isEmpty == false {
            if let password = mongo["password"]?.string?.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed), password.isEmpty == false {
                server = try Server("mongodb://\(user):\(password)@\(host):\(port)")
            } else {
                server = try Server("mongodb://\(user)@\(host):\(port)")
            }
        } else {
            server = try Server("mongodb://\(host):\(port)")
        }
        self.database = server[databaseName]
    }
    
    // MARK: - Methods
    
    func boot(_ config: Config) throws {
        
    }
    
    func boot(_ droplet: Droplet) throws {
        Logger.debug("Mongo Provider: Boot Connected: \(server.isConnected)")
    }
    
    func beforeRun(_ drop: Droplet) {
        Application.shared.database = database
        Logger.debug("Mongo Provider: Creating Indexes")
        do {
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
        } catch let error {
            Logger.error("Mongo Provider Error: \(error)")
        }
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
