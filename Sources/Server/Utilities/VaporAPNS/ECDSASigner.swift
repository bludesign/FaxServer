//
//  ECDSASigner.swift
//  App
//
//  Created by BluDesign, LLC on 5/9/18.
//

import Foundation
import Vapor
import JWT
import Console
import COpenSSL
import Crypto

struct ECDSASigner {
    static func sign(message: Data, key: Data) throws -> Data {
        var digest = try [UInt8](Digest(algorithm: .sha256).hash(message))
        let ecKey = try newECKeyPair(key: key)
        
        guard let signature = ECDSA_do_sign(&digest, Int32(digest.count), ecKey) else {
            throw JWTError(identifier: "ECDSA", reason: "signing")
        }
        
        var derEncodedSignature: UnsafeMutablePointer<UInt8>? = nil
        let derLength = i2d_ECDSA_SIG(signature, &derEncodedSignature)
        
        guard let derCopy = derEncodedSignature, derLength > 0 else {
            throw JWTError(identifier: "ECDSA", reason: "signing")
        }
        
        var derBytes = [UInt8](repeating: 0, count: Int(derLength))
        
        for b in 0..<Int(derLength) {
            derBytes[b] = derCopy[b]
        }
        
        return Data(derBytes)
    }
}

fileprivate extension Data {
    func toPointer() -> UnsafePointer<UInt8>? {
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: self.count)
        let stream = OutputStream(toBuffer: buffer, capacity: self.count)
        
        stream.open()
        self.withUnsafeBytes({ (p: UnsafePointer<UInt8>) -> Void in
            stream.write(p, maxLength: self.count)
        })
        
        stream.close()
        
        return UnsafePointer<UInt8>(buffer)
    }
}

fileprivate extension ECDSASigner {
    static func newECKey() throws -> OpaquePointer {
        guard let ecKey = EC_KEY_new_by_curve_name(NID_X9_62_prime256v1) else {
            throw JWTError(identifier: "ECDSA", reason: "createKey")
        }
        return ecKey
    }
    
    static func newECKeyPair(key: Data) throws -> OpaquePointer {
        var privateNum = BIGNUM()
        let keyData = key.toPointer()
        
        // Set private key
        
        BN_init(&privateNum)
        BN_bin2bn(keyData, Int32(key.count), &privateNum)
        let ecKey = try newECKey()
        EC_KEY_set_private_key(ecKey, &privateNum)
        
        // Derive public key
        
        let context = BN_CTX_new()
        BN_CTX_start(context)
        
        let group = EC_KEY_get0_group(ecKey)
        let publicKey = EC_POINT_new(group)
        EC_POINT_mul(group, publicKey, &privateNum, nil, nil, context)
        EC_KEY_set_public_key(ecKey, publicKey)
        
        // Release resources
        
        EC_POINT_free(publicKey)
        BN_CTX_end(context)
        BN_CTX_free(context)
        BN_clear_free(&privateNum)
        
        return ecKey
    }
    
    static func newECPublicKey(key: Data) throws -> OpaquePointer {
        var ecKey: OpaquePointer? = try newECKey()
        var publicBytesPointer: UnsafePointer? = key.toPointer()
        
        if let ecKey = o2i_ECPublicKey(&ecKey, &publicBytesPointer, key.count) {
            return ecKey
        } else {
            throw JWTError(identifier: "ECDSA", reason: "createPublicKey")
        }
    }
}
