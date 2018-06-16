//
//  CoreMiddleware.swift
//  Server
//
//  Created by BluDesign, LLC on 3/24/17.
//

import Foundation
import Vapor
import HTTP
import Leaf

final class CoreMiddleware: Middleware, Service {
    
    // MARK: - Structs
    
    struct ErrorResponse: Encodable {
        let status: HTTPResponseStatus
        let statusCode: UInt
        let title: String
        let message: String?
        
        init(_ status: HTTPResponseStatus, reason: String? = nil) {
            self.status = status
            statusCode = status.code
            title = status.reasonPhrase
            message = reason
        }
        
        private enum CodingKeys: String, CodingKey {
            case statusCode
            case title
            case message
        }
    }
    
    // MARK: - Methods
    
    func respond(to request: Request, chainingTo next: Responder) throws -> EventLoopFuture<Response> {
        let promise = request.eventLoop.newPromise(Response.self)
        
        func handleError(_ error: Swift.Error) {
            Logger.error("Error \(request.http.url): \(error)")
            let errorResponse: ErrorResponse
            if let error = error as? ServerAbort {
                errorResponse = ErrorResponse(error.status, reason: error.reason)
            } else if let error = error as? AbortError {
                errorResponse = ErrorResponse(error.status, reason: error.reason)
            } else if let debuggable = error as? Debuggable {
                errorResponse = ErrorResponse(.internalServerError, reason: debuggable.reason)
            } else {
                errorResponse = ErrorResponse(.internalServerError)
            }
            do {
                if request.jsonResponse {
                    promise.succeed(result: try request.makeJsonResponse(errorResponse, status: errorResponse.status))
                } else {
                    let leaf = try request.make(LeafRenderer.self)
                    let context: [String: String] = [
                        "errorCode": String(errorResponse.statusCode),
                        "errorTitle": errorResponse.title,
                        "errorMessage": errorResponse.message ?? ""
                    ]
                    let view = leaf.render("error", context)
                    view.do { view in
                        let response = Response(using: request.sharedContainer)
                        response.http.headers.replaceOrAdd(name: .contentType, value: "text/html; charset=utf-8")
                        response.http.body = HTTPBody(data: view.data)
                        response.http.status = .ok
                        promise.succeed(result: response)
                        }.catch { error in
                            let response = Response(using: request.sharedContainer)
                            response.http.headers.replaceOrAdd(name: .contentType, value: "text/plain")
                            response.http.body = HTTPBody(string: error.localizedDescription)
                            response.http.status = errorResponse.status
                            promise.succeed(result: response)
                    }
                }
            } catch {
                let response = Response(using: request.sharedContainer)
                response.http.headers.replaceOrAdd(name: .contentType, value: "text/plain")
                response.http.body = HTTPBody(string: "\(errorResponse.title): \(errorResponse.message ?? "Fatal Error")")
                response.http.status = errorResponse.status
                promise.succeed(result: response)
            }
        }
        
        do {
            try next.respond(to: request).do { response in
                promise.succeed(result: response)
                }.catch { error in
                    handleError(error)
            }
        } catch {
            handleError(error)
        }
        
        return promise.futureResult
    }
}
