//
//  Message.swift
//  Server
//
//  Created by BluDesign, LLC on 8/25/17.
//

import Foundation
import MongoKitten

struct Message {
    
    // MARK: - Parameters
    
    static let collectionName = "message"
    static var collection: MongoKitten.Collection {
        return MongoProvider.shared.database[collectionName]
    }
}

struct TwilioMessage: Codable {
    
    // MARK: - Parameters
    
    let sid: String
    let accountSid: String
    let messagingServiceId: String?
    let status: String?
    let from: String?
    let to: String?
    let price: String?
    let priceUnit: String?
    let mediaCount: String?
    let segmentCount: String?
    let apiVersion: String?
    
    private enum CodingKeys : String, CodingKey {
        case sid
        case accountSid = "account_sid"
        case messagingServiceId = "messaging_service_sid"
        case status
        case from
        case to
        case price
        case priceUnit = "price_unit"
        case mediaCount = "num_media"
        case segmentCount = "num_segments"
        case apiVersion = "api_version"
    }
}

struct MediaCodingKey: CodingKey {
    
    var stringValue: String
    
    init?(stringValue: String) {
        self.stringValue = stringValue
    }
    
    var intValue: Int?
    
    init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
}

struct TwilioIncommingMessage: Decodable {
    
    // MARK: - Parameters
    
    let sid: String
    let accountSid: String
    let from: String?
    let to: String?
    let body: String?
    let messagingServiceId: String?
    let mediaCount: Int?
    let segmentCount: Int?
    let status: String?
    let apiVersion: String?
    
    let fromCity: String?
    let fromState: String?
    let fromZip: String?
    let fromCountry: String?
    let toCity: String?
    let toState: String?
    let toZip: String?
    let toCountry: String?
    
    let errorCode: String?
    let errorMessage: String?
    
    let mediaItems: [Media]?
    
    struct Media {
        let url: String
        let contentType: String
    }
    
    private enum CodingKeys : String, CodingKey {
        case sid = "MessageSid"
        case accountSid = "AccountSid"
        case from = "From"
        case to = "To"
        case body = "Body"
        case messagingServiceId = "MessagingServiceSid"
        case mediaCount = "NumMedia"
        case segmentCount = "NumSegments"
        case status = "MessageStatus"
        case apiVersion = "ApiVersion"
        case fromCity = "FromCity"
        case fromState = "FromState"
        case fromZip = "FromZip"
        case fromCountry = "FromCountry"
        case toCity = "ToCity"
        case toState = "ToState"
        case toZip = "ToZip"
        case toCountry = "ToCountry"
        case errorCode = "ErrorCode"
        case errorMessage = "ErrorMessage"
        case mediaUrl
    }
    
    private struct CustomCodingKeys: CodingKey {
        var intValue: Int?
        var stringValue: String
        
        init?(stringValue: String) {
            self.stringValue = stringValue
        }
        init?(intValue: Int) {
            self.stringValue = "\(intValue)"
            self.intValue = intValue
        }
        
        static func makeKey(name: String) -> CustomCodingKeys? {
            return CustomCodingKeys(stringValue: name)
        }
    }
    
    // MARK: - Life Cycle
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sid = try container.decode(String.self, forKey: .sid)
        accountSid = try container.decode(String.self, forKey: .accountSid)
        from = try? container.decode(String.self, forKey: .from)
        to = try? container.decode(String.self, forKey: .to)
        body = try? container.decode(String.self, forKey: .body)
        messagingServiceId = try? container.decode(String.self, forKey: .messagingServiceId)
        mediaCount = (try? container.decode(String.self, forKey: .mediaCount))?.intValue
        segmentCount = (try? container.decode(String.self, forKey: .segmentCount))?.intValue
        status = try? container.decode(String.self, forKey: .status)
        apiVersion = try? container.decode(String.self, forKey: .apiVersion)
        
        fromCity = try? container.decode(String.self, forKey: .fromCity)
        fromState = try? container.decode(String.self, forKey: .fromState)
        fromZip = try? container.decode(String.self, forKey: .fromZip)
        fromCountry = try? container.decode(String.self, forKey: .fromCountry)
        toCity = try? container.decode(String.self, forKey: .toCity)
        toState = try? container.decode(String.self, forKey: .toState)
        toZip = try? container.decode(String.self, forKey: .toZip)
        toCountry = try? container.decode(String.self, forKey: .toCountry)
        
        errorCode = try? container.decode(String.self, forKey: .errorCode)
        errorMessage = try? container.decode(String.self, forKey: .errorMessage)
        
        if let mediaCount = mediaCount, mediaCount > 0 {
            Logger.info("MEida; \(mediaCount)")
            var mediaItems: [Media] = []
            let container = try decoder.container(keyedBy: CustomCodingKeys.self)
            for x in 0 ..< mediaCount {
                guard let urlKey = CustomCodingKeys.makeKey(name: "MediaUrl\(x)"), let contentTypeKey =  CustomCodingKeys.makeKey(name: "MediaContentType\(x)") else { continue }
                guard let url = try? container.decode(String.self, forKey: urlKey), let contentType = try? container.decode(String.self, forKey: contentTypeKey) else {
                    Logger.info("MMS Missing Media")
                    continue
                }
                Logger.info("URL; \(url) Type: \(contentType)")
                mediaItems.append(Media(url: url, contentType: contentType))
            }
            self.mediaItems = mediaItems
        } else {
            mediaItems = nil
        }
    }
}
