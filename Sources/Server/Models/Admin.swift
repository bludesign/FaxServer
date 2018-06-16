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
        return MongoProvider.shared.database[collectionName]
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
    
    var databaseVersion: Int {
        get {
            return document["databaseVersion"] as? Int ?? 1
        }
        set {
            document["databaseVersion"] = newValue
        }
    }
    
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
    
    var regularUserCanDelete: Bool {
        get {
            return document["regularUserCanDelete"] as? Bool ?? false
        }
        set {
            document["regularUserCanDelete"] = newValue
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
    
    var basicAuth: Bool {
        get {
            return document["basicAuth"] as? Bool ?? false
        }
        set {
            document["basicAuth"] = newValue
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
    
    var notificationEmail: String {
        get {
            return document["notificationEmail"] as? String ?? Constants.defaultEmail
        }
        set {
            document["notificationEmail"] = newValue
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
    
    var faxReceivedSendEmail: Bool {
        get {
            return document["faxReceivedSendEmail"] as? Bool ?? true
        }
        set {
            document["faxReceivedSendEmail"] = newValue
        }
    }
    
    var faxStatusSendEmail: Bool {
        get {
            return document["faxStatusSendEmail"] as? Bool ?? true
        }
        set {
            document["faxStatusSendEmail"] = newValue
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
    
    var messageSendApns: Bool {
        get {
            return document["messageSendApns"] as? Bool ?? true
        }
        set {
            document["messageSendApns"] = newValue
        }
    }
    
    var faxReceivedSendApns: Bool {
        get {
            return document["faxReceivedSendApns"] as? Bool ?? true
        }
        set {
            document["faxReceivedSendApns"] = newValue
        }
    }
    
    var faxStatusSendApns: Bool {
        get {
            return document["faxStatusSendApns"] as? Bool ?? true
        }
        set {
            document["faxStatusSendApns"] = newValue
        }
    }
    
    // MARK: - Slack
    
    var slackWebHookUrl: String? {
        get {
            return document["slackWebHookUrl"] as? String
        }
        set {
            document["slackWebHookUrl"] = newValue
        }
    }
    
    var messageSendSlack: Bool {
        get {
            return document["messageSendSlack"] as? Bool ?? true
        }
        set {
            document["messageSendSlack"] = newValue
        }
    }
    
    var faxReceivedSendSlack: Bool {
        get {
            return document["faxReceivedSendSlack"] as? Bool ?? true
        }
        set {
            document["faxReceivedSendSlack"] = newValue
        }
    }
    
    var faxStatusSendSlack: Bool {
        get {
            return document["faxStatusSendSlack"] as? Bool ?? true
        }
        set {
            document["faxStatusSendSlack"] = newValue
        }
    }
    
    // MARK: - Goolge
    
    var googleClientId: String? {
        get {
            return document["googleClientId"] as? String
        }
        set {
            document["googleClientId"] = newValue
        }
    }
    
    var googleClientSecret: String? {
        get {
            return document["googleClientSecret"] as? String
        }
        set {
            document["googleClientSecret"] = newValue
        }
    }
    
    // MARK: - Methods
    
    func save() throws {
        try Admin.collection.update("_id" == objectId, to: document)
    }
}
