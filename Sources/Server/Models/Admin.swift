//
//  Admin.swift
//  Server
//
//  Created by BluDesign, LLC on 7/2/17.
//

import Foundation
import MongoKitten

struct Admin {
    
    // MARK: - Parameters
    
    static let collectionName = "admin"
    static var collection: MongoKitten.Collection {
        return Application.shared.database[collectionName]
    }
    
    var objectId: ObjectId
    var document: Document
    
    static var settings: Admin = {
        do {
            if let document = try Admin.collection.findOne(), let objectId = document.objectId {
                return Admin(objectId: objectId, document: document)
            } else {
                let document: Document = [
                    "registrationEnabled": true
                ]
                guard let objectId = try Admin.collection.insert(document) as? ObjectId else {
                    assertionFailure("Could Not Create Admin")
                    return Admin(objectId: ObjectId(), document: Document())
                }
                return Admin(objectId: objectId, document: document)
            }
        } catch let error {
            assertionFailure("Could Not Create Admin: \(error)")
            return Admin(objectId: ObjectId(), document: Document())
        }
    }()
    
    // MARK: - Settings
    
    var timeZone: String {
        get {
            return document["timeZone"] as? String ?? TimeZone(secondsFromGMT: 0)?.identifier ?? Constants.defaultTimeZone
        }
        set {
            document["timeZone"] = newValue
        }
    }
    
    var registrationEnabled: Bool {
        get {
            return document["registrationEnabled"] as? Bool ?? false
        }
        set {
            document["registrationEnabled"] = newValue
        }
    }
    
    var messageSendEmail: Bool {
        get {
            return document["messageSendEmail"] as? Bool ?? false
        }
        set {
            document["messageSendEmail"] = newValue
        }
    }
    
    var notificationEmail: String {
        get {
            return document["notificationEmail"] as? String ?? Constants.defaultEmail
        }
        set {
            document["adminEmail"] = newValue
        }
    }
    
    var nexmoEnabled: Bool {
        get {
            return document["nexmoEnabled"] as? Bool ?? true
        }
        set {
            document["nexmoEnabled"] = newValue
        }
    }
    
    var domain: String? {
        get {
            return document["url"] as? String
        }
        set {
            document["url"] = newValue
        }
    }
    
    var domainHostname: String? {
        if let domain = domain, let url = URL(string: domain) {
            return url.host
        }
        return nil
    }
    
    var secureCookie: Bool {
        get {
            return document["secureCookie"] as? Bool ?? false
        }
        set {
            document["secureCookie"] = newValue
        }
    }
    
    // MARK: - Mailgun
    
    var mailgunApiKey: String? {
        get {
            return document["mailgunApiKey"] as? String
        }
        set {
            document["mailgunApiKey"] = newValue
        }
    }
    
    var mailgunApiUrl: String? {
        get {
            return document["mailgunApiUrl"] as? String
        }
        set {
            document["mailgunApiUrl"] = newValue
        }
    }
    
    var mailgunFromEmail: String {
        get {
            return document["mailgunFromEmail"] as? String ?? Constants.defaultEmail
        }
        set {
            document["mailgunFromEmail"] = newValue
        }
    }
    
    // MARK: - APNS
    
    var apnsBundleId: String? {
        get {
            return document["apnsBundleId"] as? String
        }
        set {
            document["apnsBundleId"] = newValue
        }
    }
    
    var apnsTeamId: String? {
        get {
            return document["apnsTeamId"] as? String
        }
        set {
            document["apnsTeamId"] = newValue
        }
    }
    
    var apnsKeyId: String? {
        get {
            return document["apnsKeyId"] as? String
        }
        set {
            document["apnsKeyId"] = newValue
        }
    }
    
    var apnsKeyPath: String? {
        get {
            return document["apnsKeyPath"] as? String
        }
        set {
            document["apnsKeyPath"] = newValue
        }
    }
    
    // MARK: - Methods
    
    func save() throws {
        try Admin.collection.update("_id" == objectId, to: document)
    }
}
