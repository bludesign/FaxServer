//
//  Device+Routes.swift
//  Server
//
//  Created by BluDesign, LLC on 8/2/17.
//

import Foundation
import Vapor
import MongoKitten

extension Device {
    
    // MARK: - Methods
    
    static func routes(_ drop: Droplet, _ group: RouteBuilder, authenticationMiddleware: AuthenticationMiddleware) {
        let protected = group.grouped([authenticationMiddleware])
        
        // MARK: Upsert Device Token
        protected.post { request in
            let userId = try request.getUserId()
            let deviceToken = try request.data.extract("deviceToken") as String
            let document: Document = [
                "deviceToken": deviceToken,
                "updatedAt": Date(),
                "userId": userId
            ]
            try Device.collection.update("deviceToken" == deviceToken, to: document, upserting: true)
            
            return Response(jsonStatus: .ok)
        }
    }
}
