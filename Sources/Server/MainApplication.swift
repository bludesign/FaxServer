//
//  MainApplication.swift
//  Server
//
//  Created by BluDesign, LLC on 3/24/17.
//

import Foundation
import Vapor
import Leaf
import MongoKitten
import Random
import Crypto

public final class MainApplication {
    
    // MARK: - Parameters
    
    static let shared = MainApplication()
    
    var random: URandom
    var application: Application
    
    // MARK: - Life Cycle
    
    init(testing: Bool = false) {
        Logger.debug("Starting Server")
        
        do {
            random = try URandom()
            
            let config = Config.default()
            let environment = try Environment.detect()
            var services = Services.default()
            
            try services.register(MainApplicationProvider())
            try services.register(LeafProvider())
            try services.register(MongoProvider.shared)
            try services.register(PushProvider())
            
            services.register(MainApplication.routes(), as: Router.self)
            services.registerMiddlewares()
            
            services.register { container -> NIOServerConfig in
                var config = NIOServerConfig.default()
                if environment.isRelease == false {
                    config.hostname = "0.0.0.0"
                }
                return config
            }
            
            application = try Application(
                config: config,
                environment: environment,
                services: services
            )
        } catch {
            print(error)
            exit(1)
        }
    }
    
    // MARK: - Methods
    
    static func makeHash(_ string: String) throws -> String {
        let key = Environment.get("HASH_KEY") ?? "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
        return try HMAC.SHA512.authenticate(string, key: key).base64EncodedString()
    }
    
    static func encrypt(_ data: LosslessDataConvertible) throws -> Data {
        let key = Environment.get("CIPHER_KEY") ?? "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
        return try Cipher(algorithm: .aes256ecb).encrypt(data, key: key)
    }
    
    static func decrypt(_ data: LosslessDataConvertible) throws -> Data {
        let key = Environment.get("CIPHER_KEY") ?? "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
        return try Cipher(algorithm: .aes256ecb).decrypt(data, key: key)
    }
    
    public static func start() {
        do {
            try MainApplication.shared.application.run()
        } catch let error {
            fatalError("MainApplication Error: \(error)")
        }
    }
}
