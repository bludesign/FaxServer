//
//  PushProvider.swift
//  Server
//
//  Created by BluDesign, LLC on 9/18/17.
//

import Foundation
import Vapor
import MongoKitten
import VaporAPNS
import CCurl

final class PushProvider: Vapor.Provider {

    // MARK: - Parameters

    static let repositoryName = "Push"
    static var apns: VaporAPNS?

    // MARK: - Life Cycle

    init(config: Config) throws {
        
    }

    // MARK: - Methods

    func boot(_ config: Config) throws {

    }

    func boot(_ droplet: Droplet) throws {

    }

    func beforeRun(_ drop: Droplet) {
        PushProvider.startApns()
    }

    static func sendPush(threadId: String, title: String, body: String, userId: ObjectId? = nil) {
        let payload = Payload(title: title, body: body)
        payload.threadId = threadId
        do {
            let devices: CollectionSlice<Document>
            if let userId = userId {
                devices = try Device.collection.find("userId" == userId, limitedTo: 10)
            } else {
                devices = try Device.collection.find(limitedTo: 10)
            }
            var deviceTokens: [String] = []
            for device in devices {
                guard let deviceToken = device["deviceToken"] as? String else { continue }
                deviceTokens.append(deviceToken)
            }
            payload.sound = "paper_tear_slow.wav"
            let pushMessage = ApplePushMessage(priority: .immediately, payload: payload, sandbox: false)
            PushProvider.apns?.send(pushMessage, to: deviceTokens, perDeviceResultHandler: { (result) in
                switch result {
                case let .error(apnsId, deviceToken, error):
                    Logger.error("APNS Push ID: \(apnsId) Token: \(deviceToken) Error: \(error)")
                case let .networkError(error):
                    Logger.error("APNS Push Network Error: \(error)")
                default:
                    break
                }
            })
        } catch let error {
            Logger.error("APNS Push Error: \(error)")
        }
    }

    static func startApns() {
        Logger.debug("Starting APNS Push Provider")
        guard let bundleId = Admin.settings.apnsBundleId, let teamId = Admin.settings.apnsTeamId, let keyId = Admin.settings.apnsKeyId, let keyPath = Admin.settings.apnsKeyPath else {
            Logger.info("APNS Push Notifications Not Configured")
            return
        }
        guard CurlVersion.checkVersion() else {
            Logger.info("APNS Push Notifications Curl Version Unsupported")
            return
        }
        let path: String
        if keyPath.hasSuffix("/") {
            path = keyPath
        } else {
            path = Application.shared.drop.config.resourcesDir.appending(keyPath)
        }
        do {
            let options = try Options(topic: bundleId, teamId: teamId, keyId: keyId, keyPath: path)
            PushProvider.apns = try VaporAPNS(options: options)
            Logger.debug("APNS Push Notifications Enabled")
        } catch let error {
            Logger.error("APNS Push Notifications Error: \(error)")
        }
        Formatter.longFormatter.timeZone = TimeZone(identifier: Admin.settings.timeZone)
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
        var arrVersionA = strVersionA.split(".").map({ Int($0) })
        guard arrVersionA.count == 3 else {
            Logger.info("APNS Push Notifications Wrong Curl Version: \(strVersionA)")
            return -1
        }
        
        var arrVersionB = strVersionB.split(".").map({ Int($0) })
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
