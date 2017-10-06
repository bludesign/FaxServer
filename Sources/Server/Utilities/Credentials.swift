//
//  Credentials.swift
//  Server
//
//  Created by BluDesign, LLC on 3/24/17.
//

import Foundation

protocol Credentials { }

struct EmailPassword: Credentials {
    let email: String
    let password: String
    
    init(email: String, password: String) {
        self.email = email
        self.password = password
    }
}

struct Totp: Credentials {
    let code: String
    let authenticityToken: String
    
    init(code: String, authenticityToken: String) {
        self.code = code
        self.authenticityToken = authenticityToken
    }
}
