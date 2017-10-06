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
    
    static func routes(_ drop: Droplet, _ group: RouteBuilder, authenticationMiddleware: AuthenticationMiddleware) {
        let protected = group.grouped([authenticationMiddleware])
        
        // MARK: Get Settings
        protected.get { request in
            if request.jsonResponse {
                var node = [
                    "registrationEnabled": (Admin.settings.registrationEnabled ? "true" : "false"),
                    "secureCookie": (Admin.settings.secureCookie ? "true" : "false"),
                    "nexmoEnabled": (Admin.settings.nexmoEnabled ? "true" : "false"),
                    "notificationEmail": Admin.settings.notificationEmail,
                    "mailgunFromEmail": Admin.settings.mailgunFromEmail,
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
                    "notificationEmail": Admin.settings.notificationEmail,
                    "mailgunFromEmail": Admin.settings.mailgunFromEmail,
                    "mailgunApiUrl": Admin.settings.mailgunApiUrl,
                    "apnsBundleId": Admin.settings.apnsBundleId,
                    "apnsTeamId": Admin.settings.apnsTeamId,
                    "apnsKeyId": Admin.settings.apnsKeyId,
                    "apnsKeyPath": Admin.settings.apnsKeyPath,
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
            
            try Admin.settings.save()
            
            if apnsUpdated {
                PushProvider.startApns()
            }
            
            if request.jsonResponse {
                return Response(jsonStatus: .unauthorized)
            }
            return Response(redirect: "/admin")
        }
    }
}
