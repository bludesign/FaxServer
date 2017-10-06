//
//  Application+Middleware.swift
//  Server
//
//  Created by BluDesign, LLC on 6/30/17.
//

import Foundation
import HTTP

extension Application {
    
    // MARK: - Parameters
    
    var middleware: [Middleware] {
        return [
            CoreMiddleware()
        ]
    }
}
