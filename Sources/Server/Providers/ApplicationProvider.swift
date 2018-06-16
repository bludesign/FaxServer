//
//  ApplicationProvider.swift
//  Server
//
//  Created by BluDesign, LLC on 3/24/17.
//

import Foundation
import Vapor

final class MainApplicationProvider: Provider {
    
    func register(_ services: inout Services) throws {
        
    }
    
    func didBoot(_ container: Container) throws -> EventLoopFuture<Void> {
        return .done(on: container)
    }
}
