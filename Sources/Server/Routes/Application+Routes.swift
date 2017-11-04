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
        Account.routes(drop, drop.grouped("account"))
        Admin.routes(drop, drop.grouped("admin"))
        Client.routes(drop, drop.grouped("client"))
        Device.routes(drop, drop.grouped("device"))
        Fax.routes(drop, drop.grouped("fax"))
        Message.routes(drop, drop.grouped("message"))
        OAuth.routes(drop, drop.grouped("oauth"))
        User.routes(drop, drop.grouped("user"))
    }
}
