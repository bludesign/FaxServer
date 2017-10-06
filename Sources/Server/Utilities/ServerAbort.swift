//
//  ServerAbort.swift
//  Server
//
//  Created by BluDesign, LLC on 8/3/17.
//

import Foundation
import Vapor
import HTTP

struct ServerAbort: Swift.Error {
    
    // MARK: - Parameters
    
    let status: Status
    let reason: String
    let file: String
    let line: Int
    let column: Int
    
    var localizedDescription: String {
        return "(\(status.statusCode) - \(status.reasonPhrase)) \(reason)"
    }
    
    // MARK: - Life Cycle
    
	init(_ status: Status, reason: String, file: String = #file, line: Int = #line, column: Int = #column) {
        self.status = status
        self.reason = reason
        self.file = file
        self.line = line
        self.column = column
    }
}

extension Status {
    
    // MARK: - Parameters
    
    var isValid: Bool {
        return 200..<300 ~= statusCode
    }
}
