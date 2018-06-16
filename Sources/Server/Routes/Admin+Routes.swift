//
//  Admin+Routes.swift
//  Server
//
//  Created by BluDesign, LLC on 7/2/17.
//

import Foundation
import Vapor
import MongoKitten

struct AdminRouter {
    
    init(router: Router) {
        let adminRouter = router.grouped(AdminAuthenticationMiddleware.self)
        
        adminRouter.get(use: get)
        adminRouter.post(use: post)
    }
    
    struct Settings: Content {
        let action: String?
        let registrationEnabled: Bool?
        let secureCookie: Bool?
        let nexmoEnabled: Bool?
        let regularUserCanDelete: Bool?
        let messageSendEmail: Bool?
        let faxReceivedSendEmail: Bool?
        let faxStatusSendEmail: Bool?
        let messageSendApns: Bool?
        let faxReceivedSendApns: Bool?
        let faxStatusSendApns: Bool?
        let messageSendSlack: Bool?
        let faxReceivedSendSlack: Bool?
        let faxStatusSendSlack: Bool?
        let basicAuth: Bool?
        let notificationEmail: String?
        let domain: String?
        let apnsBundleId: String?
        let apnsTeamId: String?
        let apnsKeyId: String?
        let apnsKeyPath: String?
        let slackWebHookUrl: String?
        let timeZone: String?
        var timeZones: [String]?
        var timeZoneData: String?
        let mailgunFromEmail: String?
        let mailgunApiUrl: String?
        var mailgunApiKey: String?
        var mailgunApiKeySet: Bool?
        var googleClientId: String?
        var googleClientSecret: String?
        var googleClientSecretSet: Bool?
        var admin: Bool?
        var contactsEnabled: Bool?
        
        init() {
            action = nil
            registrationEnabled = Admin.settings.registrationEnabled
            secureCookie = Admin.settings.secureCookie
            nexmoEnabled = Admin.settings.nexmoEnabled
            regularUserCanDelete = Admin.settings.regularUserCanDelete
            messageSendEmail = Admin.settings.messageSendEmail
            faxReceivedSendEmail = Admin.settings.faxReceivedSendEmail
            faxStatusSendEmail = Admin.settings.faxStatusSendEmail
            messageSendApns = Admin.settings.messageSendApns
            faxReceivedSendApns = Admin.settings.faxReceivedSendApns
            faxStatusSendApns = Admin.settings.faxStatusSendApns
            messageSendSlack = Admin.settings.messageSendSlack
            faxReceivedSendSlack = Admin.settings.faxReceivedSendSlack
            faxStatusSendSlack = Admin.settings.faxStatusSendSlack
            basicAuth = Admin.settings.basicAuth
            notificationEmail = Admin.settings.notificationEmail
            domain = Admin.settings.domain
            apnsBundleId = Admin.settings.apnsBundleId
            apnsTeamId = Admin.settings.apnsTeamId
            apnsKeyId = Admin.settings.apnsKeyId
            apnsKeyPath = Admin.settings.apnsKeyPath
            slackWebHookUrl = Admin.settings.slackWebHookUrl
            timeZone = Admin.settings.timeZone
            mailgunFromEmail = Admin.settings.mailgunFromEmail
            mailgunApiUrl = Admin.settings.mailgunApiUrl
            mailgunApiKeySet = Admin.settings.mailgunApiKey != nil
            googleClientSecretSet = Admin.settings.googleClientSecret != nil
            googleClientId = Admin.settings.googleClientId
        }
    }
    
    // MARK: GET
    func get(_ request: Request) throws -> Future<ServerResponse> {
        return request.globalAsync { promise in
            var settings = Settings()
            let timeZones = TimeZone.knownTimeZoneIdentifiers.sorted { $0.localizedCaseInsensitiveCompare($1) == ComparisonResult.orderedAscending }
            
            if request.jsonResponse {
                settings.timeZones = timeZones
                return promise.submit(try settings.encoded(request: request))
            }
            var timeZoneData: String = ""
            let currentTimeZone = Admin.settings.timeZone
            for timeZone in timeZones {
                let string: String
                if timeZone == currentTimeZone {
                    string = "<option value=\"\(timeZone)\" selected>\(timeZone.replacingOccurrences(of: "_", with: " "))</option>"
                } else {
                    string = "<option value=\"\(timeZone)\">\(timeZone.replacingOccurrences(of: "_", with: " "))</option>"
                }
                timeZoneData.append(string)
            }
            settings.timeZoneData = timeZoneData
            settings.admin = try? request.authentication().permission.isAdmin
            settings.contactsEnabled = Admin.settings.googleClientId != nil && Admin.settings.googleClientSecret != nil
            return promise.submit(try request.renderEncoded("admin", settings))
        }
    }
    
    // MARK: POST
    func post(_ request: Request) throws -> Future<ServerResponse> {
        return request.globalAsync { promise in
            let settings = try request.content.syncDecode(Settings.self)
            
            if let domain = settings.domain {
                guard let url = URL(string: domain), let domain = url.domain else {
                    throw ServerAbort(.badRequest, reason: "Domain format is invalid")
                }
                Admin.settings.domain = domain
            }
            if let registrationEnabled = settings.registrationEnabled {
                Admin.settings.registrationEnabled = registrationEnabled
            }
            if let secureCookie = settings.secureCookie {
                Admin.settings.secureCookie = secureCookie
            }
            if let nexmoEnabled = settings.nexmoEnabled {
                Admin.settings.nexmoEnabled = nexmoEnabled
            }
            if let regularUserCanDelete = settings.regularUserCanDelete {
                Admin.settings.regularUserCanDelete = regularUserCanDelete
            }
            
            if let messageSendEmail = settings.messageSendEmail {
                Admin.settings.messageSendEmail = messageSendEmail
            }
            if let faxReceivedSendEmail = settings.faxReceivedSendEmail {
                Admin.settings.faxReceivedSendEmail = faxReceivedSendEmail
            }
            if let faxStatusSendEmail = settings.faxStatusSendEmail {
                Admin.settings.faxStatusSendEmail = faxStatusSendEmail
            }
            
            if let messageSendApns = settings.messageSendApns {
                Admin.settings.messageSendApns = messageSendApns
            }
            if let faxReceivedSendApns = settings.faxReceivedSendApns {
                Admin.settings.faxReceivedSendApns = faxReceivedSendApns
            }
            if let faxStatusSendApns = settings.faxStatusSendApns {
                Admin.settings.faxStatusSendApns = faxStatusSendApns
            }
            
            if let messageSendSlack = settings.messageSendSlack {
                Admin.settings.messageSendSlack = messageSendSlack
            }
            if let faxReceivedSendSlack = settings.faxReceivedSendSlack {
                Admin.settings.faxReceivedSendSlack = faxReceivedSendSlack
            }
            if let faxStatusSendSlack = settings.faxStatusSendSlack {
                Admin.settings.faxStatusSendSlack = faxStatusSendSlack
            }
            
            if let basicAuth = settings.basicAuth {
                Admin.settings.basicAuth = basicAuth
            }
            if let notificationEmail = settings.notificationEmail {
                Admin.settings.notificationEmail = notificationEmail
            }
            
            if let domain = (settings.domain?.isEmpty == true ? settings.domain : settings.domain?.url?.domain) {
                Admin.settings.domain = domain
            }
            
            var apnsUpdated = false
            if let apnsBundleId = settings.apnsBundleId {
                Admin.settings.apnsBundleId = apnsBundleId
                apnsUpdated = true
            }
            if let apnsTeamId = settings.apnsTeamId {
                Admin.settings.apnsTeamId = apnsTeamId
                apnsUpdated = true
            }
            if let apnsKeyId = settings.apnsKeyId {
                Admin.settings.apnsKeyId = apnsKeyId
                apnsUpdated = true
            }
            if let apnsKeyPath = settings.apnsKeyPath {
                Admin.settings.apnsKeyPath = apnsKeyPath
                apnsUpdated = true
            }
            if apnsUpdated {
                PushProvider.startApns(container: request.sharedContainer)
            }
            
            if let slackWebHookUrl = settings.slackWebHookUrl {
                Admin.settings.slackWebHookUrl = slackWebHookUrl
            }
            if let timeZoneString = settings.timeZone {
                if let timeZone = TimeZone(identifier: timeZoneString) {
                    Admin.settings.timeZone = timeZoneString
                    Formatter.longFormatter.timeZone = timeZone
                } else {
                    Logger.error("Invalid Timezone: \(timeZoneString)")
                }
            }

            if let mailgunFromEmail = settings.mailgunFromEmail {
                Admin.settings.mailgunFromEmail = mailgunFromEmail
            }
            if let mailgunApiKey = settings.mailgunApiKey, mailgunApiKey.isHiddenText == false {
                Admin.settings.mailgunApiKey = mailgunApiKey
            }
            if let mailgunApiUrl = settings.mailgunApiUrl {
                Admin.settings.mailgunApiUrl = mailgunApiUrl
            }
            
            if let googleClientId = settings.googleClientId {
                Admin.settings.googleClientId = googleClientId
            }
            if let googleClientSecret = settings.googleClientSecret, googleClientSecret.isHiddenText == false {
                Admin.settings.googleClientSecret = googleClientSecret
            }
            
            try Admin.settings.save()
            
            return promise.succeed(result: request.serverStatusRedirect(status: .ok, to: "/admin"))
        }
    }
}
