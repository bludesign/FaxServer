//
//  Admin+Routes.swift
//  Server
//
//  Created by BluDesign, LLC on 7/2/17.
//

import Foundation
import Vapor
import MongoKitten

extension Admin {
    
    // MARK: - Methods
    
    static func routes(_ drop: Droplet, _ group: RouteBuilder) {
        let protected = group.grouped([AuthenticationMiddleware.shared])
        
        // MARK: Get Settings
        protected.get { request in
            if request.jsonResponse {
                var node = [
                    "registrationEnabled": (Admin.settings.registrationEnabled ? "true" : "false"),
                    "secureCookie": (Admin.settings.secureCookie ? "true" : "false"),
                    "nexmoEnabled": (Admin.settings.nexmoEnabled ? "true" : "false"),
                    "messageSendEmail": (Admin.settings.messageSendEmail ? "true" : "false"),
                    "faxReceivedSendEmail": (Admin.settings.faxReceivedSendEmail ? "true" : "false"),
                    "faxStatusSendEmail": (Admin.settings.faxStatusSendEmail ? "true" : "false"),
                    "messageSendApns": (Admin.settings.messageSendApns ? "true" : "false"),
                    "faxReceivedSendApns": (Admin.settings.faxReceivedSendApns ? "true" : "false"),
                    "faxStatusSendApns": (Admin.settings.faxStatusSendApns ? "true" : "false"),
                    "messageSendSlack": (Admin.settings.messageSendSlack ? "true" : "false"),
                    "faxReceivedSendSlack": (Admin.settings.faxReceivedSendSlack ? "true" : "false"),
                    "faxStatusSendSlack": (Admin.settings.faxStatusSendSlack ? "true" : "false"),
                    "notificationEmail": Admin.settings.notificationEmail,
                    "mailgunFromEmail": Admin.settings.mailgunFromEmail,
                    "mailgunApiUrl": Admin.settings.mailgunApiUrl,
                    "slackWebHookUrl": Admin.settings.slackWebHookUrl,
                    "timeZone": Admin.settings.timeZone,
                    "domain": Admin.settings.domain
                ]
                node["apnsBundleId"] = Admin.settings.apnsBundleId
                node["apnsTeamId"] = Admin.settings.apnsTeamId
                node["apnsKeyId"] = Admin.settings.apnsKeyId
                node["apnsKeyPath"] = Admin.settings.apnsKeyPath
                node["mailgunApiUrl"] = Admin.settings.mailgunApiUrl
                return try JSON(node: node).makeResponse()
            } else {
                var timeZoneData: String = ""
                let currentTimeZone = Admin.settings.timeZone
                let timeZones = TimeZone.knownTimeZoneIdentifiers.sorted { $0.localizedCaseInsensitiveCompare($1) == ComparisonResult.orderedAscending }
                for timeZone in timeZones {
                    let string: String
                    if timeZone == currentTimeZone {
                        string = "<option value=\"\(timeZone)\" selected>\(timeZone.replacingOccurrences(of: "_", with: " "))</option>"
                    } else {
                        string = "<option value=\"\(timeZone)\">\(timeZone.replacingOccurrences(of: "_", with: " "))</option>"
                    }
                    timeZoneData.append(string)
                }
                return try drop.view.make("admin", [
                    (Admin.settings.registrationEnabled ? "userRegistrationEnabled" : "userRegistrationDisabled"): "checked",
                    (Admin.settings.secureCookie ? "secureCookieEnabled" : "secureCookieDisabled"): "checked",
                    (Admin.settings.nexmoEnabled ? "nexmoEnabled" : "nexmoDisabled"): "checked",
                    (Admin.settings.messageSendEmail ? "messageSendEmailEnabled" : "messageSendEmailDisabled"): "checked",
                    (Admin.settings.faxReceivedSendEmail ? "faxReceivedSendEmailEnabled" : "faxReceivedSendEmailDisabled"): "checked",
                    (Admin.settings.faxStatusSendEmail ? "faxStatusSendEmailEnabled" : "faxStatusSendEmailDisabled"): "checked",
                    (Admin.settings.messageSendApns ? "messageSendApnsEnabled" : "messageSendApnsDisabled"): "checked",
                    (Admin.settings.faxReceivedSendApns ? "faxReceivedSendApnsEnabled" : "faxReceivedSendApnsDisabled"): "checked",
                    (Admin.settings.faxStatusSendApns ? "faxStatusSendApnsEnabled" : "faxStatusSendApnsDisabled"): "checked",
                    (Admin.settings.messageSendSlack ? "messageSendSlackEnabled" : "messageSendSlackDisabled"): "checked",
                    (Admin.settings.faxReceivedSendSlack ? "faxReceivedSendSlackEnabled" : "faxReceivedSendSlackDisabled"): "checked",
                    (Admin.settings.faxStatusSendSlack ? "faxStatusSendSlackEnabled" : "faxStatusSendSlackDisabled"): "checked",
                    "notificationEmail": Admin.settings.notificationEmail,
                    "mailgunFromEmail": Admin.settings.mailgunFromEmail,
                    "mailgunApiUrl": Admin.settings.mailgunApiUrl,
                    "apnsBundleId": Admin.settings.apnsBundleId,
                    "apnsTeamId": Admin.settings.apnsTeamId,
                    "apnsKeyId": Admin.settings.apnsKeyId,
                    "apnsKeyPath": Admin.settings.apnsKeyPath,
                    "slackWebHookUrl": Admin.settings.slackWebHookUrl,
                    "timeZoneData": timeZoneData,
                    "domain": Admin.settings.domain
                ])
            }
        }
        
        // MARK: Update Settings
        protected.post { request in
            if let domain = try? request.data.extract("domain") as String {
                guard let url = URL(string: domain), let domain = url.domain else {
                    throw ServerAbort(.badRequest, reason: "Domain format is invalid")
                }
                Admin.settings.domain = domain
            }
            if let registrationEnabled = try? request.data.extract("registrationEnabled") as Bool {
                Admin.settings.registrationEnabled = registrationEnabled
            }
            if let secureCookie = try? request.data.extract("secureCookie") as Bool {
                Admin.settings.secureCookie = secureCookie
            }
            if let nexmoEnabled = try? request.data.extract("nexmoEnabled") as Bool {
                Admin.settings.nexmoEnabled = nexmoEnabled
            }
            if let timeZoneString = try? request.data.extract("timeZone") as String {
                if let timeZone = TimeZone(identifier: timeZoneString) {
                    Admin.settings.timeZone = timeZoneString
                    Formatter.longFormatter.timeZone = timeZone
                } else {
                    Logger.error("Invalid Timezone: \(timeZoneString)")
                }
            }
            if let notificationEmail = try? request.data.extract("notificationEmail") as String {
                Admin.settings.notificationEmail = notificationEmail
            }
            
            if let mailgunFromEmail = try? request.data.extract("mailgunFromEmail") as String {
                Admin.settings.mailgunFromEmail = mailgunFromEmail
            }
            if let mailgunApiKey = try? request.data.extract("mailgunApiKey") as String {
                Admin.settings.mailgunApiKey = mailgunApiKey
            }
            if let mailgunApiUrl = try? request.data.extract("mailgunApiUrl") as String {
                Admin.settings.mailgunApiUrl = mailgunApiUrl
            }
            
            var apnsUpdated = false
            if let apnsBundleId = try? request.data.extract("apnsBundleId") as String {
                Admin.settings.apnsBundleId = apnsBundleId
                apnsUpdated = true
            }
            if let apnsTeamId = try? request.data.extract("apnsTeamId") as String {
                Admin.settings.apnsTeamId = apnsTeamId
                apnsUpdated = true
            }
            if let apnsKeyId = try? request.data.extract("apnsKeyId") as String {
                Admin.settings.apnsKeyId = apnsKeyId
                apnsUpdated = true
            }
            if let apnsKeyPath = try? request.data.extract("apnsKeyPath") as String {
                Admin.settings.apnsKeyPath = apnsKeyPath
                apnsUpdated = true
            }
            if apnsUpdated {
                PushProvider.startApns()
            }
            
            if let slackWebHookUrl = try? request.data.extract("slackWebHookUrl") as String {
                Admin.settings.slackWebHookUrl = slackWebHookUrl
            }
            
            if let messageSendEmail = try? request.data.extract("messageSendEmail") as Bool {
                Admin.settings.messageSendEmail = messageSendEmail
            }
            if let faxReceivedSendEmail = try? request.data.extract("faxReceivedSendEmail") as Bool {
                Admin.settings.faxReceivedSendEmail = faxReceivedSendEmail
            }
            if let faxStatusSendEmail = try? request.data.extract("faxStatusSendEmail") as Bool {
                Admin.settings.faxStatusSendEmail = faxStatusSendEmail
            }
            
            if let messageSendApns = try? request.data.extract("messageSendApns") as Bool {
                Admin.settings.messageSendApns = messageSendApns
            }
            if let faxReceivedSendApns = try? request.data.extract("faxReceivedSendApns") as Bool {
                Admin.settings.faxReceivedSendApns = faxReceivedSendApns
            }
            if let faxStatusSendApns = try? request.data.extract("faxStatusSendApns") as Bool {
                Admin.settings.faxStatusSendApns = faxStatusSendApns
            }
            
            if let messageSendSlack = try? request.data.extract("messageSendSlack") as Bool {
                Admin.settings.messageSendSlack = messageSendSlack
            }
            if let faxReceivedSendSlack = try? request.data.extract("faxReceivedSendSlack") as Bool {
                Admin.settings.faxReceivedSendSlack = faxReceivedSendSlack
            }
            if let faxStatusSendSlack = try? request.data.extract("faxStatusSendSlack") as Bool {
                Admin.settings.faxStatusSendSlack = faxStatusSendSlack
            }
            
            try Admin.settings.save()
            
            if request.jsonResponse {
                return Response(jsonStatus: .unauthorized)
            }
            return Response(redirect: "/admin")
        }
    }
}
