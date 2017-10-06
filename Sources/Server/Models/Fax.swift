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
        return Application.shared.database[collectionName]
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
