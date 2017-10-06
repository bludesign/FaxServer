//
//  Application+Routes.swift
//  Server
//
//  Created by BluDesign, LLC on 3/24/17.
//

import Foundation
import Vapor

extension Application {
    
    // MARK: - Methods
    
    func routes(_ drop: Droplet) {
        drop.get { _ in
            return Response(redirect: "/admin")
        }
        Account.routes(drop, drop.grouped("account"), authenticationMiddleware: authenticationMiddleware)
        Admin.routes(drop, drop.grouped("admin"), authenticationMiddleware: authenticationMiddleware)
        Client.routes(drop, drop.grouped("client"), authenticationMiddleware: authenticationMiddleware)
        Device.routes(drop, drop.grouped("device"), authenticationMiddleware: authenticationMiddleware)
        Fax.routes(drop, drop.grouped("fax"), authenticationMiddleware: authenticationMiddleware)
        Message.routes(drop, drop.grouped("message"), authenticationMiddleware: authenticationMiddleware)
        OAuth.routes(drop, drop.grouped("oauth"), authenticationMiddleware: authenticationMiddleware)
        User.routes(drop, drop.grouped("user"), authenticationMiddleware: authenticationMiddleware)
    }
}
