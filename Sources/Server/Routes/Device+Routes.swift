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
    
    static func routes(_ drop: Droplet, _ group: RouteBuilder) {
        let protected = group.grouped([AuthenticationMiddleware.shared])
        
        // MARK: Upsert Device Token
        protected.post { request in
            let userId = try request.getUserId()
            let deviceToken = try request.data.extract("deviceToken") as String
            let deviceName = try request.data.extract("deviceName") as String
            let document: Document = [
                "deviceToken": deviceToken,
                "deviceName": deviceName,
                "updatedAt": Date(),
                "userId": userId
            ]
            try Device.collection.update("deviceToken" == deviceToken, to: document, upserting: true)
            
            return Response(jsonStatus: .ok)
        }
        
        protected.post("testPush") { request in
            let userId = try request.getUserId()
            PushProvider.sendPush(threadId: "test", title: "Test Notification", body: "Test Push Notification", userId: userId)
            if request.jsonResponse {
                return Response(jsonStatus: .ok)
            }
            return Response(redirect: "/user/\(userId.hexString)")
        }
    }
}
