//
//  Application+Routes.swift
//  Server
//
//  Created by BluDesign, LLC on 3/24/17.
//

import Foundation
import Vapor

extension MainApplication {
    
    // MARK: - Methods
    
    static func routes() -> EngineRouter {
        let router = EngineRouter.default()
        router.get { request -> Response in
            return request.redirect(to: "/fax")
        }
        
        _ = AccountRouter(router: router.grouped("account"))
        _ = AdminRouter(router: router.grouped("admin"))
        _ = ContactRouter(router: router.grouped("contact"))
        _ = FaxClientRouter(router: router.grouped("client"))
        _ = FaxRouter(router: router.grouped("fax"))
        _ = MessageRouter(router: router.grouped("message"))
        _ = OAuthRouter(router: router.grouped("oauth"))
        _ = PushDeviceRouter(router: router.grouped("pushDevice"))
        _ = UserRouter(router: router.grouped("user"))
        
        return router
    }
}
