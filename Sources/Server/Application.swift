//
//  Application.swift
//  Server
//
//  Created by BluDesign, LLC on 3/24/17.
//

import Foundation
import Vapor
import LeafProvider
import MongoKitten
import Random

public final class Application {
    
    // MARK: - Parameters
    
    static let shared = Application()
    
    var authenticationMiddleware = AuthenticationMiddleware()
    var database: MongoKitten.Database!
    var random: URandom
    var drop: Droplet
    
    // MARK: - Life Cycle
    
    init(testing: Bool = false) {
        Logger.debug("Starting Server")
        do {
            let config = try Config()
            try config.addProvider(MongoProvider.self)
            try config.addProvider(LeafProvider.Provider.self)
            try config.addProvider(ApplicationProvider.self)
            try config.addProvider(PushProvider.self)
            config.addConfigurable(middleware: CoreMiddleware(), name: "coreMiddleware")
            drop = try Droplet(config: config)
            guard let randomPath = drop.config["app", "randomPath"]?.string else {
                fatalError("Missing Random Path")
            }
            random = try URandom(path: randomPath)
            routes(drop)
        } catch let error {
            fatalError("Application Error: \(error)")
        }
    }
    
    // MARK: - Methods
    
    static func makeHash(_ string: String) throws -> String {
        return try Application.shared.drop.hash.make(string).base64EncodedString
    }
    
    public static func start() {
        do {
            try Application.shared.drop.run()
        } catch let error {
            fatalError("Application Error: \(error)")
        }
    }
}
