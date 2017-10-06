//
//  AuthenicationMiddleware.swift
//  Server
//
//  Created by BluDesign, LLC on 8/9/17.
//

import Foundation
import Vapor
import MongoKitten

private extension URI {
    
    // MARK: - Parameters
    
    var extendedPath: String {
        var path = self.path
        if let query = query {
            path += "?\(query)"
        }
        if let fragment = fragment {
            path += "#\(fragment)"
        }
        return path
    }
}

final class AuthenticationMiddleware: Middleware {
    
    // MARK: - Methods
    
    func respond(to request: Request, chainingTo next: Responder) throws -> Response {
        guard request.userId != nil else {
            if request.jsonResponse {
                return Response(jsonStatus: .unauthorized)
            }
            return Response(redirect: "/user/login?referrer=\(request.uri.extendedPath)")
        }
        return try next.respond(to: request)
    }
}

extension Request {
    var userId: ObjectId? {
        if let userId = storage["userId"] as? ObjectId {
            return userId
        }
        let token: String
        if let authorization = headers["Authorization"]?.components(separatedBy: " ").last {
            token = authorization
        } else if let cookie = cookies["Server-Auth"] {
            token = cookie
        } else {
            return nil
        }
        do {
            let tokenHash = try Application.makeHash(token)
            guard var accessToken = try AccessToken.collection.findOne("token" == tokenHash) else { return nil }
            guard let tokenExpiration = accessToken["tokenExpires"] as? Date else { return nil }
            guard Date() < tokenExpiration else { return nil }
            guard let userId = accessToken["userId"] as? ObjectId else { return nil }
            storage["userId"] = userId
            return accessToken["userId"] as? ObjectId
        } catch {
            return nil
        }
    }
    
    func getUserId() throws -> ObjectId {
        guard let userId = self.userId else {
            throw ServerAbort(.notFound, reason: "userId missing")
        }
        return userId
    }
}
