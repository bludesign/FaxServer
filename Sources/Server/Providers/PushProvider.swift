//
//  PushProvider.swift
//  Server
//
//  Created by BluDesign, LLC on 9/18/17.
//

import Foundation
import Vapor
import MongoKitten
import CCurl
import Jobs

final class PushProvider: Vapor.Provider {
    
    // MARK: - Parameters
    
    static let repositoryName = "Push"
    static var apns: VaporAPNS?
    
    // MARK: - Life Cycle
    
    private static func send(payload: Payload, deviceToken: String, retryCount: Int = 1) {
        let pushMessage = ApplePushMessage(priority: .immediately, payload: payload, sandbox: false)
        do {
            guard let provider = PushProvider.apns else { return }
            try provider.send(pushMessage, to: deviceToken)
        } catch let error {
            if let error = error as? APNSError, case APNSError.tooManyProviderTokenUpdates = error  {
                Logger.info("APNS Rate Limited Retry In \(5 * retryCount) Minutes")
                Jobs.oneoff(delay: Duration.seconds(300 * Double(retryCount))) {
                    send(payload: payload, deviceToken: deviceToken, retryCount: retryCount + 1)
                }
            } else {
                Logger.error("APNS Push Error: \(error)")
            }
        }
    }
    
    // MARK: - Methods
    
    func register(_ services: inout Services) throws {
        
    }
    
    func willBoot(_ container: Container) throws -> Future<Void> {
        return .done(on: container)
    }
    
    func didBoot(_ container: Container) throws -> EventLoopFuture<Void> {
        PushProvider.startApns(container: container)
        return .done(on: container)
    }
    
    static func sendPush(title: String, body: String, userId: ObjectId? = nil) {
        let payload = Payload(title: title, body: body, sound: "default")
        do {
            let devices: CollectionSlice<Document>
            if let userId = userId {
                devices = try PushDevice.collection.find("userId" == userId, limitedTo: 10)
            } else {
                devices = try PushDevice.collection.find(limitedTo: 10)
            }
            
            for device in devices {
                guard let deviceToken = device["deviceToken"] as? String else { continue }
                send(payload: payload, deviceToken: deviceToken)
            }
        } catch let error {
            Logger.error("APNS Push Error: \(error)")
        }
    }
    
    static func startApns(container: Container) {
        Logger.debug("Starting APNS Push Provider")
        guard let bundleId = Admin.settings.apnsBundleId, let teamId = Admin.settings.apnsTeamId, let keyId = Admin.settings.apnsKeyId, let keyPath = Admin.settings.apnsKeyPath else {
            Logger.info("APNS Push Notifications Not Configured")
            return
        }
        guard CurlVersion.checkVersion() else {
            Logger.info("APNS Push Notifications Curl Version Unsupported")
            return
        }
        do {
            let directory = try container.make(DirectoryConfig.self).workDir
            let path: String
            if keyPath.hasSuffix("/") {
                path = keyPath
            } else {
                path = "\(directory)Resources/\(keyPath)"
            }
            
            let options = try Options(topic: bundleId, teamId: teamId, keyId: keyId, keyPath: path)
            PushProvider.apns = try VaporAPNS(options: options)
            Logger.debug("APNS Push Notifications Enabled")
        } catch let error {
            Logger.error("APNS Push Notifications Error: \(error)")
        }
        Formatter.longFormatter.timeZone = TimeZone(identifier: Admin.settings.timeZone)
    }
    
    static func sendSlack(objectName: String, objectLink: String?, title: String, titleLink: String?, isError: Bool, date: Date = Date(), fields: [(title: String, value: String)]) {
        guard let webHookUrl = Admin.settings.slackWebHookUrl, let url = Admin.settings.domain else { return }
        do {
            let requestClient = try MainApplication.shared.application.make(Client.self)
            let headers = HTTPHeaders([
                ("Accept", "application/json"),
                ("Content-Type", "application/json")
            ])
            
            struct Notification: Content {
                let username: String = "fax"
                let icon_url = "https://bludesign.biz/faxserver.png"
                let attachments: [Attachment]
                
                struct Attachment: Content {
                    var fallback: String?
                    var color: String?
                    var author_name: String?
                    var title: String?
                    var footer: String = "Fax Server"
                    var ts: Double?
                    var author_link: String?
                    var title_link: String?
                    var fields: [Field] = []
                    
                    struct Field: Content {
                        let title: String
                        let value: String
                        let short: Bool = false
                    }
                }
            }
            
            var attachment = Notification.Attachment()
            attachment.fallback = "\(objectName) - \(title)"
            attachment.color = (isError ? "#d50000" : "#45a455")
            attachment.author_name = objectName
            attachment.title = title
            attachment.ts = date.timeIntervalSince1970
            if let objectLink = objectLink {
                attachment.author_link = "\(url)\(objectLink)"
            }
            if let titleLink = titleLink {
                attachment.title_link = "\(url)\(titleLink)"
            }
            for field in fields {
                attachment.fields.append(Notification.Attachment.Field(title: field.title, value: field.value))
            }
            let notification = Notification(attachments: [attachment])
            
            requestClient.post(webHookUrl, headers: headers, beforeSend: { request in
                try request.content.encode(notification)
            }).do { response in
                guard response.http.status.isValid else {
                    Logger.error("Error Sending Slack Status: \(response.http.status)")
                    return
                }
            }.catch { error in
                Logger.error("Error Sending Slack: \(error)")
            }
        } catch let error {
            Logger.error("Error Sending Slack: \(error)")
        }
    }
    
    static func sendTest(userId: ObjectId) {
        PushProvider.sendPush(title: "Test Notification", body: "Test Push Notification - \(Date().longString)", userId: userId)
        PushProvider.sendSlack(objectName: "Test Notification", objectLink: nil, title: "Test Push Notification - \(Date().longString)", titleLink: "/admin", isError: false, fields: [])
    }
}

private struct CurlVersion {
    static func checkVersion() -> Bool {
        let version = curl_version_info(CURLVERSION_FOURTH)
        let verBytes = version?.pointee.version
        let versionString = String.init(cString: verBytes!)
        
        guard CurlVersion.checkVersionNumber(versionString, "7.51.0") >= 0 else {
            return false
        }
        
        let features = version?.pointee.features
        
        if (features! & CURL_VERSION_HTTP2) == CURL_VERSION_HTTP2 {
            return true
        } else {
            return false
        }
    }
    
    private static func checkVersionNumber(_ strVersionA: String, _ strVersionB: String) -> Int {
        var arrVersionA = strVersionA.split(separator: ".").map({ Int($0) })
        guard arrVersionA.count == 3 else {
            Logger.info("APNS Push Notifications Wrong Curl Version: \(strVersionA)")
            return -1
        }
        
        var arrVersionB = strVersionB.split(separator: ".").map({ Int($0) })
        guard arrVersionB.count == 3 else {
            Logger.info("APNS Push Notifications Wrong Curl Version: \(strVersionB)")
            return -1
        }
        
        let intVersionA = (100000000 * arrVersionA[0]!) + (1000000 * arrVersionA[1]!) + (10000 * arrVersionA[2]!)
        let intVersionB = (100000000 * arrVersionB[0]!) + (1000000 * arrVersionB[1]!) + (10000 * arrVersionB[2]!)
        
        if intVersionA > intVersionB {
            return 1
        } else if intVersionA < intVersionB {
            return -1
        } else {
            return 0
        }
    }
}
