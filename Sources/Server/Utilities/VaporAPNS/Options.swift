//
//  APNSSettings.swift
//  VaporAPNS
//
//  Created by Matthijs Logemann on 17/09/2016.
//
//

import Foundation

/// Specific configuration options to be passed to `VaporAPNS`
public struct Options: CustomStringConvertible {
    public enum Port: Int {
        case p443 = 443, p2197 = 2197
    }
    
    public var topic: String
    public var port: Port = .p443
    
    // Authentication method: authentication key
    public var teamId: String?
    public var keyId: String?
    public var privateKey: String?

    public var debugLogging: Bool = false
    
    public var disableCurlCheck: Bool = false
    public var forceCurlInstall: Bool = false
    
    public init(topic: String, teamId: String, keyId: String, keyPath: String, port: Port = .p443, debugLogging: Bool = false) throws {
        self.teamId = teamId
        self.topic = topic
        self.keyId = keyId

        self.debugLogging = debugLogging

        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: keyPath) else {
            throw InitializeError.keyFileDoesNotExist
        }

        self.privateKey = try keyPath.tokenString()
    }
    
    public var description: String {
        return
            "Topic \(topic)" +
                "\nPort \(port.rawValue)" +
                "\nPort \(port.rawValue)" +
                "\nTOK - Key ID: \(String(describing: keyId))" +
                "\nTOK - Private key: \(String(describing: privateKey))"
    }
}
