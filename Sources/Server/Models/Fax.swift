//
//  Fax.swift
//  Server
//
//  Created by BluDesign, LLC on 6/29/17.
//

import Foundation
import MongoKitten

struct Fax {
    
    // MARK: - Parameters
    
    static let collectionName = "fax"
    static var collection: MongoKitten.Collection {
        return MongoProvider.shared.database[collectionName]
    }
}

extension String {
    
    // MARK: - Parameters
    
    var quailityString: String {
        if self == "superfine" {
            return "Super Fine"
        }
        return capitalized
    }
    var statusString: String {
        if self == "no-answer" {
            return "No Answer"
        }
        return capitalized
    }
}

struct TwilioError: Codable {
    let code: Int
    let message: String
}

struct TwilioFax: Codable {
    
    // MARK: - Parameters
    
    let sid: String
    let accountSid: String
    let mediaSid: String?
    let dateUpdated: Date?
    let dateCreated: Date?
    let status: String?
    let direction: String?
    let from: String?
    let to: String?
    let price: String?
    let priceUnit: String?
    let url: String?
    let duration: Int?
    let pages: Int?
    let quality: String?
    let apiVersion: String?
    let mediaUrl: String?
    
    private enum CodingKeys : String, CodingKey {
        case sid
        case accountSid = "account_sid"
        case mediaSid = "media_sid"
        case dateUpdated = "date_updated"
        case dateCreated = "date_created"
        case status
        case direction
        case from
        case to
        case price
        case priceUnit = "price_unit"
        case url
        case duration
        case pages = "num_pages"
        case quality
        case apiVersion = "api_version"
        case mediaUrl = "media_url"
    }
}

struct TwilioIncommingFax: Codable {
    
    // MARK: - Parameters
    
    let sid: String
    let accountSid: String
    let from: String?
    let to: String?
    let remoteStationId: String?
    let status: String?
    let apiVersion: String?
    let pages: Int?
    let mediaUrl: String?
    let errorCode: String?
    let errorMessage: String?
    
    private enum CodingKeys : String, CodingKey {
        case sid = "FaxSid"
        case accountSid = "AccountSid"
        case from = "From"
        case to = "To"
        case remoteStationId = "RemoteStationId"
        case status = "FaxStatus"
        case pages = "NumPages"
        case apiVersion = "ApiVersion"
        case mediaUrl = "OriginalMediaUrl"
        case errorCode = "ErrorCode"
        case errorMessage = "ErrorMessage"
    }
}
