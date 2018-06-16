//
//  Contact.swift
//  Server
//
//  Created by BluDesign, LLC on 3/9/18.
//

import Foundation
import MongoKitten

struct Contact {
    
    // MARK: - Structs
    
    struct PhoneNumber {
        let type: String
        let number: String
        let primary: Bool
    }
    
    // MARK: - Parameters
    
    var objectId: String
    var firstName: String?
    var lastName: String?
    var organization: String?
    var groupId: String?
    var groupName: String?
    var phoneNumbers: [String: PhoneNumber] = [:]
    
    static let collectionName = "contact"
    static var collection: MongoKitten.Collection {
        return MongoProvider.shared.database[collectionName]
    }
    
    var mainPhoneNumbers: (home: PhoneNumber?, work: PhoneNumber?, cell: PhoneNumber?) {
        var phoneNumbers = self.phoneNumbers
        
        var home: PhoneNumber?
        var work: PhoneNumber?
        var cell: PhoneNumber?
        if let phoneNumber = phoneNumbers["home"] {
            home = phoneNumber
            phoneNumbers.removeValue(forKey: "home")
        }
        if let phoneNumber = phoneNumbers["work"] {
            work = phoneNumber
            phoneNumbers.removeValue(forKey: "work")
        }
        if let phoneNumber = phoneNumbers["mobile"] {
            cell = phoneNumber
            phoneNumbers.removeValue(forKey: "mobile")
        }
        
        if (home == nil || work == nil || cell == nil) && phoneNumbers.count > 0 {
            for (type, phoneNumber) in phoneNumbers where phoneNumber.primary {
                if home == nil {
                    home = phoneNumber
                } else if work == nil {
                    work = phoneNumber
                } else if cell == nil {
                    cell = phoneNumber
                } else {
                    break
                }
                phoneNumbers.removeValue(forKey: type)
                break
            }
            for (type, phoneNumber) in phoneNumbers {
                if home == nil {
                    home = phoneNumber
                } else if work == nil {
                    work = phoneNumber
                } else if cell == nil {
                    cell = phoneNumber
                } else {
                    break
                }
                phoneNumbers.removeValue(forKey: type)
            }
        }
        
        return (home: home, work: work, cell: cell)
    }
    
    // MARK: - Life Cycle
    
    init(objectId: String) {
        self.objectId = objectId
    }
    
    init?(document: Document) {
        guard let objectId = document["contactId"] as? String else { return nil }
        self.objectId = objectId
        firstName = document["firstName"] as? String
        lastName = document["lastName"] as? String
        organization = document["organization"] as? String
        groupId = document["groupId"] as? String
        groupName = document["groupName"] as? String
        if let phoneNumberDocuments = document["phoneNumbers"] as? Document {
            for (type, value) in phoneNumberDocuments {
                guard let phoneNumberDocument = value as? Document, let number = phoneNumberDocument["number"] as? String, let primary = phoneNumberDocument["primary"] as? Bool else { continue }
                phoneNumbers[type] = PhoneNumber(type: type, number: number, primary: primary)
            }
        }
    }
    
    // MARK: - Methods
    
    func document(userId: ObjectId, groupName: String?) -> Document {
        var document = Document()
        document["contactId"] = objectId
        document["userId"] = userId
        document["firstName"] = firstName
        document["lastName"] = lastName
        document["organization"] = organization
        document["groupId"] = groupId
        document["groupName"] = groupName
        var phoneNumberDocument: [String: Document] = [:]
        for (key, value) in phoneNumbers {
            phoneNumberDocument[key] = [
                "number": value.number,
                "primary": value.primary
            ]
        }
        document["phoneNumbers"] = phoneNumberDocument
        return document
    }
}

struct ContactGroups: Decodable {
    let contactGroups: [Group]
    let totalItems: Int
    let nextPageToken: String?
    let nextSyncToken: String?
    
    struct Group: Decodable {
        let resourceName: String
        let etag: String?
        let metadata: Metadata?
        let groupType: GroupType
        let name: String
        let formattedName: String
        let memberResourceNames: [String]?
        let memberCount: Int?
        
        enum GroupType: String, Decodable {
            case unspectifited = "GROUP_TYPE_UNSPECIFIED"
            case user = "USER_CONTACT_GROUP"
            case system = "SYSTEM_CONTACT_GROUP"
        }
        
        struct Metadata: Decodable {
            let updateTime: Date
            let deleted: Bool?
        }
    }
}

struct Connections: Decodable {
    let connections: [Person]
    let totalItems: Int
    let nextPageToken: String?
    let nextSyncToken: String?
    
    struct FieldMetadata: Decodable {
        let primary: Bool?
        let verified: Bool?
    }
    
    struct Person: Decodable {
        let resourceName: String
        let etag: String?
        let phoneNumbers: [PhoneNumber]?
        let organizations: [Organization]?
        let names: [Name]?
        let memberships: [Membership]?
        
        struct Organization: Decodable {
            let name: String?
            let metadata: FieldMetadata
        }
        
        struct PhoneNumber: Decodable {
            let value: String
            let canonicalForm: String?
            let type: String?
            let formattedType: String?
            let metadata: FieldMetadata
        }
        
        struct Name: Decodable {
            let givenName: String?
            let familyName: String?
            let displayName: String
        }
        
        struct Membership: Decodable {
            let metadata: FieldMetadata
            let contactGroupMembership: ContactGroupMembership
            
            struct ContactGroupMembership: Decodable {
                let contactGroupId: String
            }
        }
    }
}
