//
//  ApplicationProvider.swift
//  Server
//
//  Created by BluDesign, LLC on 3/24/17.
//

import Foundation
import Vapor

final class ApplicationProvider: Vapor.Provider {
    
    // MARK: - Parameters
    
    static let repositoryName = "Application"
    
    // MARK: - Life Cycle
    
    init(config: Config) throws {
        
    }
    
    // MARK: - Methods
    
    func boot(_ config: Config) throws {
        
    }
    
    func boot(_ droplet: Droplet) throws {
        
    }
    
    func beforeRun(_ drop: Droplet) {
        
    }
}
