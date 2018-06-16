//
//  PushDevice+Routes.swift
//  Server
//
//  Created by BluDesign, LLC on 8/2/17.
//

import Foundation
import Vapor
import MongoKitten

struct PushDeviceRouter {
    
    init(router: Router) {
        let protectedRouter = router.grouped(AuthenticationMiddleware.self)
        
        protectedRouter.post(use: post)
        protectedRouter.post("testPush", use: postTestPush)
    }
    
    // MARK: POST
    func post(_ request: Request) throws -> Future<ServerResponse> {
        struct FormData: Codable {
            let deviceToken: String
            let deviceName: String
        }
        return try request.content.decode(FormData.self).flatMap(to: ServerResponse.self) { formData in
            let userId = try request.authentication().userId
            let pushDevice: Document = [
                "deviceToken": formData.deviceToken,
                "deviceName": formData.deviceName,
                "updatedAt": Date(),
                "userId": userId
            ]
            try PushDevice.collection.update("deviceToken" == formData.deviceToken, to: pushDevice, upserting: true)
            return try request.statusEncoded(status: .ok)
        }
    }
    
    // MARK: POST testPush
    func postTestPush(_ request: Request) throws -> Future<ServerResponse> {
        let userId = try request.authentication().userId
        PushProvider.sendTest(userId: userId)
        if request.jsonResponse {
            return try request.statusEncoded(status: .ok)
        }
        return try request.redirectEncoded(to: "/user/\(userId.hexString)")
    }
}
