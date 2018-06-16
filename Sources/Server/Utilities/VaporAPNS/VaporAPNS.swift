//
//  VaporAPNS.swift
//  VaporAPNS
//
//  Created by Nathan Flurry on 9/26/16.
//
//

import Foundation
import CCurl
import JWT
import Console

open class VaporAPNS {
    private struct ResponseReason: Decodable {
        let reason: String
    }
    
    fileprivate var options: Options
    fileprivate var curlHandle: UnsafeMutableRawPointer

    public init(options: Options) throws {
        self.options = options

        self.curlHandle = curl_easy_init()

        curlHelperSetOptBool(curlHandle, CURLOPT_VERBOSE, options.debugLogging ? CURL_TRUE : CURL_FALSE)
        
        curlHelperSetOptInt(curlHandle, CURLOPT_HTTP_VERSION, CURL_HTTP_VERSION_2_0)
    }

    open func send(_ message: ApplePushMessage, to deviceToken: String) throws {
        // Set URL
        let url = ("\(self.hostURL(message.sandbox))/3/device/\(deviceToken)")
        curlHelperSetOptString(curlHandle, CURLOPT_URL, url)

        // force set port to 443
        curlHelperSetOptInt(curlHandle, CURLOPT_PORT, options.port.rawValue)

        // Follow location
        curlHelperSetOptBool(curlHandle, CURLOPT_FOLLOWLOCATION, CURL_TRUE)

        // set POST request
        curlHelperSetOptBool(curlHandle, CURLOPT_POST, CURL_TRUE)

        // setup payload
        // TODO: Message payload

        guard let optionsPrivateKey = options.privateKey, let optionsTeamId = options.teamId, let optionsKeyId = options.keyId else {
            throw APNSError(errorReason: "Options not configured")
        }
        var postFieldsString = try JSONEncoder().encode(PayloadHolder(aps: message.payload))

        postFieldsString.withUnsafeMutableBytes() { (t: UnsafeMutablePointer<Int8>) -> Void in
            curlHelperSetOptString(curlHandle, CURLOPT_POSTFIELDS, t)
        }
        curlHelperSetOptInt(curlHandle, CURLOPT_POSTFIELDSIZE, postFieldsString.count)

        // Tell CURL to add headers
        curlHelperSetOptBool(curlHandle, CURLOPT_HEADER, CURL_TRUE)

        //Headers
        let headers = self.requestHeaders(for: message)
        var curlHeaders: UnsafeMutablePointer<curl_slist>?

        guard let privateKey = Data(base64Encoded: optionsPrivateKey) else {
            throw APNSError(errorReason: "Nil private key data")
        }
        struct APNSPayload: JWTPayload {
            let iss: IssuerClaim
            let iat: IssuedAtClaim = IssuedAtClaim(value: Date())

            func verify() throws {

            }
        }
        let payload = APNSPayload(iss: IssuerClaim(value: optionsTeamId))
        var jwt = JWT(payload: payload)
        jwt.header.kid = optionsKeyId
        let algorithm = CustomJWTAlgorithm(name: "ES256", sign: { plaintext in
            return try ECDSASigner.sign(message: plaintext.convertToData(), key: privateKey)
        }, verify: { signature, plaintext in
            return true
        })
        let signer = JWTSigner(algorithm: algorithm)
        let tokenData = try jwt.sign(using: signer)
        guard let tokenString = String(data: tokenData, encoding: .utf8) else {
            throw APNSError(errorReason: "Nil token Data")
        }
        
        curlHeaders = curl_slist_append(curlHeaders, "authorization: bearer \(tokenString.replacingOccurrences(of: " ", with: ""))")

        curlHeaders = curl_slist_append(curlHeaders, "User-Agent: Server/1.0.0")
        for header in headers {
            curlHeaders = curl_slist_append(curlHeaders, "\(header.key): \(header.value)")
        }
        curlHeaders = curl_slist_append(curlHeaders, "Accept: application/json")
        curlHeaders = curl_slist_append(curlHeaders, "Content-Type: application/json");
        curlHelperSetOptList(curlHandle, CURLOPT_HTTPHEADER, curlHeaders)

        // Get response
        var writeStorage = WriteStorage()
        curlHelperSetOptWriteFunc(curlHandle, &writeStorage) { (ptr, size, nMemb, privateData) -> Int in
            let storage = privateData?.assumingMemoryBound(to: WriteStorage.self)
            let realsize = size * nMemb

            var bytes: [UInt8] = [UInt8](repeating: 0, count: realsize)
            memcpy(&bytes, ptr!, realsize)

            for byte in bytes {
                storage?.pointee.data.append(byte)
            }
            return realsize
        }

        let ret = curl_easy_perform(curlHandle)

        if ret == CURLE_OK {
            // Create string from Data
            guard let str = String(data: writeStorage.data, encoding: .utf8) else {
                throw APNSError(errorReason: "Nil Data")
            }
            
            // Split into two pieces by '\r\n\r\n' as the response has two newlines before the returned data. This causes us to have two pieces, the headers/crap and the server returned data
            let splittedString = str.components(separatedBy: "\r\n\r\n")
            
            // Ditch the first part and only get the useful data part
            let responseData = splittedString[1]

            if responseData.isEmpty == false, let reason = try? JSONDecoder().decode(ResponseReason.self, from: responseData) {
                throw APNSError(errorReason: reason.reason)
            }

            // Do some cleanup
//            curl_easy_cleanup(curlHandle)
            curl_slist_free_all(curlHeaders)
        } else {
            guard let error = curl_easy_strerror(ret), let errorString = String(utf8String: error) else {
                throw APNSError(errorReason: "Nil Error")
            }

//            curl_easy_cleanup(curlHandle)
            curl_slist_free_all(curlHeaders)

            throw APNSError(errorReason: errorString)
        }
    }

    fileprivate func requestHeaders(for message: ApplePushMessage) -> [String: String] {
        let expirationDate: Int = Int(message.expirationDate?.timeIntervalSince1970.rounded() ?? 0)
        var headers: [String : String] = [
            "apns-id": message.messageId,
            "apns-expiration": "\(expirationDate)",
            "apns-priority": "\(message.priority.rawValue)",
            "apns-topic": message.topic ?? options.topic
        ]

        if let collapseId = message.collapseIdentifier {
            headers["apns-collapse-id"] = collapseId
        }

        if let threadId = message.threadIdentifier {
            headers["thread-id"] = threadId
        }

        return headers
    }

    fileprivate class WriteStorage {
        var data = Data()
    }
}

extension VaporAPNS {
    fileprivate func hostURL(_ development: Bool) -> String {
        if development {
            return "https://api.development.push.apple.com"
        } else {
            return "https://api.push.apple.com"
        }
    }
}
