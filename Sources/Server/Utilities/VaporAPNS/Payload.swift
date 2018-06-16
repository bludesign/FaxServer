//
//  Payload.swift
//  VaporAPNS
//
//  Created by Matthijs Logemann on 01/10/2016.
//
//

import Foundation

public struct PayloadHolder: Codable {
    public let aps: Payload
}

public struct Payload: Codable {
    public struct Alert: Codable {
        private enum CodingKeys: String, CodingKey {
            case title = "title"
            case subtitle = "subtitle"
            case body = "body"
            case titleLocKey = "title-loc-key"
            case titleLocArgs = "title-loc-args"
            case actionLocKey = "action-loc-key"
            case locKey = "loc-key"
            case locArgs = "loc-args"
            case launchImage = "launch-image"
        }
        /// A short string describing the purpose of the notification. Apple Watch displays this string as part of the notification interface. This string is displayed only briefly and should be crafted so that it can be understood quickly. This key was added in iOS 8.2.
        public var title: String?
        // A secondary description of the reason for the alert.
        public var subtitle: String?
        /// The text of the alert message. Can be nil if using titleLocKey
        public var body: String?
        /// The key to a title string in the Localizable.strings file for the current localization. The key string can be formatted with %@ and %n$@ specifiers to take the variables specified in the titleLocArgs array.
        public var titleLocKey: String?
        /// Variable string values to appear in place of the format specifiers in titleLocKey.
        public var titleLocArgs: [String]?
        /// If a string is specified, the system displays an alert that includes the Close and View buttons. The string is used as a key to get a localized string in the current localization to use for the right button’s title instead of “View”.
        public var actionLocKey: String?
        /// A key to an alert-message string in a Localizable.strings file for the current localization (which is set by the user’s language preference). The key string can be formatted with %@ and %n$@ specifiers to take the variables specified in the bodyLocArgs array.
        public var locKey: String?
        /// Variable string values to appear in place of the format specifiers in locKey.
        public var locArgs: [String]?
        /// The filename of an image file in the app bundle, with or without the filename extension. The image is used as the launch image when users tap the action button or move the action slider. If this property is not specified, the system either uses the previous snapshot, uses the image identified by the UILaunchImageFile key in the app’s Info.plist file, or falls back to Default.png.
        public var launchImage: String?
    }
    
    private enum CodingKeys: String, CodingKey {
        case alert = "alert"
        case badge = "badge"
        case sound = "sound"
        case contentAvailable = "content-available"
        case category = "category"
        case threadId = "thread-id"
        case mutableContent = "mutable-content"
    }
    
    public var alert: Alert = Alert()
    /// The number to display as the badge of the app icon.
    public var badge: Int?
    /// The name of a sound file in the app bundle or in the Library/Sounds folder of the app’s data container. The sound in this file is played as an alert. If the sound file doesn’t exist or default is specified as the value, the default alert sound is played.
    public var sound: String?
    /// Silent push notification. This automatically ignores any other push message keys (title, body, ect.) and only the extra key-value pairs are added to the final payload
    public var contentAvailable: Bool?
    /// a category that is used by iOS 10+ notifications
    public var category: String?
    /// When displaying notifications, the system visually groups notifications with the same thread identifier together.
    public var threadId: String?
    /// A Boolean indicating whether the payload contains content that can be modified by an iOS 10+ Notification Service Extension (media, encrypted content, ...)
    public var mutableContent: Bool?
}

public extension Payload {
    public init(title: String, body: String? = nil, badge: Int? = nil, sound: String? = nil) {
        self.init()
        self.alert.title = title
        self.alert.body = body
        self.badge = badge
        self.sound = sound
    }
    
    /// A simple, already made, Content-Available payload
    public static var contentAvailable: Payload {
        var payload = Payload()
        payload.contentAvailable = true
        return payload
    }
}

extension Payload: Equatable {
    public static func ==(lhs: Payload, rhs: Payload) -> Bool {
        guard lhs.badge == rhs.badge else { return false }
        guard lhs.alert.title == rhs.alert.title else { return false }
        guard lhs.alert.body == rhs.alert.body else { return false }
        guard lhs.alert.titleLocKey == rhs.alert.titleLocKey else { return false }
        guard lhs.alert.titleLocArgs != nil && rhs.alert.titleLocArgs != nil && lhs.alert.titleLocArgs == rhs.alert.titleLocArgs else { return false }
        guard lhs.alert.actionLocKey == rhs.alert.actionLocKey else { return false }
        guard lhs.alert.locKey == rhs.alert.locKey else { return false }
        guard lhs.alert.locArgs != nil && rhs.alert.locArgs != nil && lhs.alert.locArgs == rhs.alert.locArgs else { return false }
        guard lhs.alert.launchImage == rhs.alert.launchImage else { return false }
        guard lhs.sound == rhs.sound else { return false }
        guard lhs.contentAvailable == rhs.contentAvailable else { return false }
        guard lhs.threadId == rhs.threadId else { return false }
        return true
    }
}
