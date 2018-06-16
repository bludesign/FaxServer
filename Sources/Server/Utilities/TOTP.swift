//
//  TOTP.swift
//  OTPKit
//
//  Created by Chris Amanse on 06/09/2016.
//  https://github.com/chrisamanse/OTPKit
//
//  MIT License
//
//  Copyright (c) 2016 Joe Christopher Paul Amanse
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//

import Foundation
import Crypto

struct TOTP {
    
    // MARK: - Methods
    
    static func randomToken() throws -> String {
        let data = try MainApplication.shared.random.generateData(count: 20)
        return Base32.encode(data)
    }
    
    static func generate(key: String, timeInterval: TimeInterval = Date().timeIntervalSince1970, period: TimeInterval = 30, digits: Int = 6, hashFunction: HMAC = HMAC.SHA1) throws -> String {
        let key = try Base32.decode(key)
        let counter = UInt64(timeInterval / period).bigEndian
        let message = Data(from: counter)
        let hmac = try hashFunction.authenticate(message, key: key)
        let offset = Int((hmac.last ?? 0x00) & 0x0f)
        let truncated = hmac.withUnsafeBytes { (bytePointer: UnsafePointer<UInt8>) -> UInt32 in
            let offsetPointer = bytePointer.advanced(by: offset)
            return offsetPointer.withMemoryRebound(to: UInt32.self, capacity: MemoryLayout<UInt32>.size) { $0.pointee.bigEndian }
        }
        let password = String((truncated & 0x7fffffff) % UInt32(pow(10, Float(digits))))
        let paddingCount = digits - password.count
        if paddingCount != 0 {
            return String(repeating: "0", count: paddingCount) + password
        } else {
            return password
        }
    }
}

private struct Base32 {
    
    // MARK: - Enums
    
    enum Base32Error: Error {
        case invalidCharacter(character: Character)
    }
    
    // MARK: - Methods
    
    static func encode(_ data: Data) -> String {
        var characters: [Character] = []
        let pieceLength = 5
        for index in stride(from: data.startIndex, to: data.endIndex, by: pieceLength) {
            let stride = index + pieceLength
            let upperLimitIndex = stride < data.endIndex ? stride : data.endIndex
            let piece = data[index ..< upperLimitIndex]
            var integer: UInt64 = 0
            
            for (index, byte) in piece.enumerated() {
                let shiftLeftsCount = (4 - index) * 8
                let shifted = UInt64(byte) << UInt64(shiftLeftsCount)
                
                integer = integer | shifted
            }
            
            for index2 in 0..<8 {
                let bytesLeft = index.distance(to: data.endIndex)
                if bytesLeft < 5 {
                    let paddingCount: Int = {
                        switch bytesLeft {
                        case 1: return 6
                        case 2: return 4
                        case 3: return 3
                        case 4: return 1
                        default: return 0
                        }
                    }()
                    
                    if paddingCount > 7 - index2 {
                        for _ in 0 ..< paddingCount {
                            characters.append(Character("="))
                        }
                        break
                    }
                }
                
                let shiftRightCount = (7 - index2) * 5
                let nickel = (integer >> UInt64(shiftRightCount)) & 0x1f
                if let character = character(for: UInt8(nickel)) {
                    characters.append(character)
                }
            }
        }
        
        return String(characters)
    }
    
    static func decode(_ string: String) throws -> Data {
        guard !string.isEmpty else {
            return Data()
        }
        
        var bytes: [UInt8] = []
        var lowerBoundIndex = string.startIndex
        var upperBoundIndex = string.startIndex
        
        repeat {
            lowerBoundIndex = upperBoundIndex
            upperBoundIndex = string.index(upperBoundIndex, offsetBy: 8, limitedBy: string.endIndex) ?? string.endIndex
            
            let substring = string[lowerBoundIndex ..< upperBoundIndex]
            let decodedBytes = substring.lazy.map { value(for: $0) }
            var fiveByte: UInt64 = 0
            
            for (index, someByte) in decodedBytes.enumerated() {
                guard let byte = someByte else {
                    let stringIndex = substring.index(substring.startIndex, offsetBy: index)
                    throw Base32Error.invalidCharacter(character: substring[stringIndex])
                }
                let shiftLeftsCount: UInt64 = (7 - UInt64(index)) * 5
                let shiftedNickel = UInt64(byte) << shiftLeftsCount
                fiveByte = fiveByte | shiftedNickel
            }
            for index in 0..<5 {
                let shiftRightsCount: UInt64 = (4 - UInt64(index)) * 8
                let shifted = fiveByte >> shiftRightsCount
                let byte = UInt8(shifted & 0x00000000ff)
                bytes.append(byte)
            }
        } while upperBoundIndex < string.endIndex
        
        var trailingCount = 0
        var index: String.CharacterView.Index? = string.index(string.startIndex, offsetBy: string.count - 1)
        while let i = index, string[i] == "=" && trailingCount < 6 {
            trailingCount += 1
            index = string.index(i, offsetBy: -1, limitedBy: string.startIndex)
        }
        
        let paddedBytesCount: Int = {
            switch trailingCount {
            case 1: return 1
            case 3: return 2
            case 4: return 3
            case 6: return 4
            default: return 0
            }
        }()
        
        bytes.removeLast(paddedBytesCount)
        
        return Data(bytes)
    }
    
    private static func character(for value: UInt8) -> Character? {
        let unicodeScalarValue: UInt32?
        
        switch value {
        case 0...25:
            unicodeScalarValue = "A".unicodeScalars.first!.value + UInt32(value)
        case 26...31:
            unicodeScalarValue = "2".unicodeScalars.first!.value + UInt32(value) - 26
        default:
            unicodeScalarValue = nil
        }
        
        if let value = unicodeScalarValue, let unicode = UnicodeScalar(value) {
            return Character(unicode)
        } else {
            return nil
        }
    }
    
    private static func value(for character: Character) -> UInt8? {
        let unicodeScalarValue = String(character).unicodeScalars.first!.value
        
        switch unicodeScalarValue {
        case 50...55:
            return UInt8(unicodeScalarValue - 24)
        case 61:
            return 0x00
        case 65...90:
            return UInt8(unicodeScalarValue - 65)
        default:
            return nil
        }
    }
}

private extension Data {
    init<T: BinaryInteger>(from value: T) {
        let valuePointer = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer {
            valuePointer.deallocate(capacity: 1)
        }
        
        valuePointer.pointee = value
        
        let bytesPointer = valuePointer.withMemoryRebound(to: UInt8.self, capacity: MemoryLayout<UInt8>.size) { $0 }
        
        self.init(bytes: bytesPointer, count: MemoryLayout<T>.size)
    }
}
