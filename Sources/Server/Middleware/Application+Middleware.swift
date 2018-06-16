//
//  Application+Middleware.swift
//  Server
//
//  Created by BluDesign, LLC on 6/30/17.
//

import Foundation
import Vapor
import HTTP

extension Services {
    
    mutating func registerMiddlewares() {
        var middlewares = MiddlewareConfig()
        middlewares.use(FileMiddleware.self)
        middlewares.use(CoreMiddleware.self)
        register { container -> CoreMiddleware in
            return CoreMiddleware()
        }
        
        register { container -> AuthenticationMiddleware in
            return AuthenticationMiddleware()
        }
        register { container -> AdminAuthenticationMiddleware in
            return AdminAuthenticationMiddleware()
        }
        register { container -> BasicAuthenticationMiddleware in
            return BasicAuthenticationMiddleware()
        }
        register { container -> AuthenticationStorage in
            return AuthenticationStorage()
        }
        
        register(middlewares)
    }
}
