//
//  CoreMiddleware.swift
//  Server
//
//  Created by BluDesign, LLC on 3/24/17.
//

import Foundation
import Vapor
import HTTP

final class CoreMiddleware: Middleware {
    
    // MARK: - Methods
    
    func respond(to request: Request, chainingTo next: Responder) throws -> Response {
        do {
            let response = try next.respond(to: request)
            response.headers["Access-Control-Allow-Origin"] = request.headers["Origin"] ?? "*"
            response.headers["Access-Control-Allow-Headers"] = "X-Requested-With, Origin, Content-Type, Accept"
            response.headers["Access-Control-Allow-Methods"] = "POST, GET, PUT, OPTIONS, DELETE, PATCH"
            response.headers["Version"] = "API v1.0"
            return response
        } catch let error {
            Logger.error("Error \(request.uri): \(error)")
            let statusCode: Int
            let title: String
            let message: String?
            if let error = error as? ServerAbort {
                statusCode = error.status.statusCode
                title = error.status.reason
                message = error.reason
            } else {
                let status: Status = Status(error)
                statusCode = status.statusCode
                title = status.reason
                message = nil
            }
            if request.jsonResponse {
                if let message = message {
                    return try JSON(node: [ "error": [
                        "errorCode": statusCode,
                        "title": title,
                        "message": message
                    ]]).makeResponse()
                } else {
                    return try JSON(node: [ "error": [
                        "errorCode": statusCode,
                        "title": title
                    ]]).makeResponse()
                }
            } else {
                return try Application.shared.drop.view.make("error", [
                    "errorCode": statusCode,
                    "errorTitle": title,
                    "errorMessage": message ?? ""
                ]).makeResponse()
            }
        }
    }
}

extension Request {
    
    // MARK: - Parameters
    
    var isPreflight: Bool {
        return method == .options && headers["Access-Control-Request-Method"] != nil
    }
}

extension Status {
    
    // MARK: - Life Cycle
    
    internal init(_ error: Error) {
        if let abort = error as? AbortError {
            self = abort.status
        } else {
            self = .internalServerError
        }
    }
}
