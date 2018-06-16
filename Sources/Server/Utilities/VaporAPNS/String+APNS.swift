//
//  String+APNS.swift
//  VaporAPNS
//
//  Created by Nathan Flurry on 9/26/16.
//
//

import Foundation
import CLibreSSL
import Core

extension String {
    private func newECKey() throws -> OpaquePointer {
        guard let ecKey = EC_KEY_new_by_curve_name(NID_X9_62_prime256v1) else {
            throw TokenError.Unknown
        }
        return ecKey
    }
    
    func tokenString() throws -> String {
        guard FileManager.default.fileExists(atPath: self) else {
            throw TokenError.invalidAuthKey
        }

        // Fold p8 file and write it back to the file
        let fileString = try String.init(contentsOfFile: self, encoding: .utf8)
        guard
            let privateKeyString =
            fileString.collapseWhitespace.trimmingCharacters(in: .whitespaces).between(
                "-----BEGIN PRIVATE KEY-----",
                "-----END PRIVATE KEY-----"
            )?.trimmingCharacters(in: .whitespaces)
        else {
            throw TokenError.invalidTokenString
        }
        let splittedText = privateKeyString.splitByLength(64)
        let newText = "-----BEGIN PRIVATE KEY-----\n\(splittedText.joined(separator: "\n"))\n-----END PRIVATE KEY-----"
        try newText.write(toFile: self, atomically: false, encoding: .utf8)


        var pKey = EVP_PKEY_new()

        let fp = fopen(self, "r")

        PEM_read_PrivateKey(fp, &pKey, nil, nil)

        fclose(fp)

        let ecKey = EVP_PKEY_get1_EC_KEY(pKey)

        EC_KEY_set_conv_form(ecKey, POINT_CONVERSION_UNCOMPRESSED)
        
        let bn = EC_KEY_get0_private_key(ecKey)
        guard let privKeyBigNum = BN_bn2hex(bn), let privKeyBigNumString = String(validatingUTF8: privKeyBigNum) else {
            throw TokenError.Unknown
        }

        let privateKey = "00\(privKeyBigNumString)"

        guard let privData = try privateKey.dataFromHexadecimalString() else {
            throw TokenError.Unknown
        }
        
        let privBase64String = privData.base64EncodedString()
        return privBase64String
    }
    
    
    /// Create `NSData` from hexadecimal string representation
    ///
    /// This takes a hexadecimal representation and creates a `NSData` object. Note, if the string has any spaces or non-hex characters (e.g. starts with '<' and with a '>'), those are ignored and only hex characters are processed.
    ///
    /// - returns: Data represented by this hexadecimal string.
    
    func dataFromHexadecimalString() throws -> Data? {
        var data = Data(capacity: count / 2)
        let regex = try NSRegularExpression(pattern: "[0-9a-f]{1,2}", options: .caseInsensitive)
        var failed = false
        regex.enumerateMatches(in: self, options: [], range: NSMakeRange(0, count)) { match, flags, stop in
            guard let match = match else {
                failed = true
                return
            }
            let byteString = self[match.range.location..<match.range.location + match.range.length]
            guard var num = UInt8(byteString, radix: 16) else {
                failed = true
                return
            }
            data.append(&num, count: 1)
        }
        guard failed == false else {
            throw TokenError.Unknown
        }
        return data
    }
    
    func splitByLength(_ length: Int) -> [String] {
        var result = [String]()
        var collectedCharacters = [Character]()
        collectedCharacters.reserveCapacity(length)
        var count = 0
        
        for character in self {
            collectedCharacters.append(character)
            count += 1
            if (count == length) {
                // Reached the desired length
                count = 0
                result.append(String(collectedCharacters))
                collectedCharacters.removeAll(keepingCapacity: true)
            }
        }
        
        // Append the remainder
        if collectedCharacters.isEmpty == false {
            result.append(String(collectedCharacters))
        }
        
        return result
    }
}

extension String {
    func range(from nsRange: NSRange) -> Range<String.Index>? {
        guard
            let from16 = utf16.index(utf16.startIndex, offsetBy: nsRange.location, limitedBy: utf16.endIndex),
            let to16 = utf16.index(from16, offsetBy: nsRange.length, limitedBy: utf16.endIndex),
            let from = String.Index(from16, within: self),
            let to = String.Index(to16, within: self)
            else { return nil }
        return from ..< to
    }
}

extension String {
    func between(_ left: String, _ right: String) -> String? {
        guard let leftRange = range(of:left), let rightRange = range(of: right, options: .backwards), left != right && leftRange.upperBound != rightRange.lowerBound else { return nil }
        return String(self[leftRange.upperBound...index(before: rightRange.lowerBound)])
    }
    
    subscript(_ r: CountableRange<Int>) -> String {
        get {
            let startIndex = self.index(self.startIndex, offsetBy: r.lowerBound)
            let endIndex = self.index(self.startIndex, offsetBy: r.upperBound)
            return String(self[startIndex..<endIndex])
        }
    }
    
    subscript(_ range: CountableClosedRange<Int>) -> String {
        get {
            return self[range.lowerBound..<range.upperBound + 1]
        }
    }
    
    subscript(safe range: CountableRange<Int>) -> String {
        get {
            if count == 0 { return "" }
            let lower = range.lowerBound < 0 ? 0 : range.lowerBound
            let upper = range.upperBound < 0 ? 0 : range.upperBound
            let s = index(startIndex, offsetBy: lower, limitedBy: endIndex) ?? endIndex
            let e = index(startIndex, offsetBy: upper, limitedBy: endIndex) ?? endIndex
            return String(self[s..<e])
        }
    }
    
    subscript(safe range: CountableClosedRange<Int>) -> String {
        get {
            if count == 0 { return "" }
            let closedEndIndex = index(endIndex, offsetBy: -1, limitedBy: startIndex) ?? startIndex
            let lower = range.lowerBound < 0 ? 0 : range.lowerBound
            let upper = range.upperBound < 0 ? 0 : range.upperBound
            let s = index(startIndex, offsetBy: lower, limitedBy: closedEndIndex) ?? closedEndIndex
            let e = index(startIndex, offsetBy: upper, limitedBy: closedEndIndex) ?? closedEndIndex
            return String(self[s...e])
        }
    }
    
    func substring(_ startIndex: Int, length: Int) -> String {
        let start = self.index(self.startIndex, offsetBy: startIndex)
        let end = self.index(self.startIndex, offsetBy: startIndex + length)
        return String(self[start..<end])
    }
    
    subscript(i: Int) -> Character {
        get {
            let index = self.index(self.startIndex, offsetBy: i)
            return self[index]
        }
    }
}

extension Data {
    func hexString() -> String {
        var hexString = ""
        for byte in self {
            hexString += String(format: "%02X", byte)
        }
        
        return hexString
    }
}
