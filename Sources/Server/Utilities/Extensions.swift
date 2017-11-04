//
//  Extensions.swift
//  Server
//
//  Created by BluDesign, LLC on 4/2/17.
//

import Foundation
import Vapor
import MongoKitten
import HTTP
import ExtendedJSON
import SMTP
import FormData
import Multipart
import Crypto
import Validation

extension URI {
    var domain: String {
        if let port = port {
            return "\(scheme)://\(hostname):\(port)"
        } else {
            return "\(scheme)://\(hostname)"
        }
    }
}

extension URL {
    var domain: String? {
        guard let host = host, let scheme = scheme else {
            return nil
        }
        if let port = port {
            return "\(scheme)://\(host):\(port)"
        } else {
            return "\(scheme)://\(host)"
        }
    }
}

extension Array where Iterator.Element == UInt8 {
    var base64EncodedString: String {
        return Data(bytes: self).base64EncodedString()
    }
}

extension ObjectId: NodeConvertible {
    public init(node: Node) throws {
        let stringId = try node.get() as String
        try self.init(stringId)
    }
    
    public func makeNode(in context: Context?) throws -> Node {
        return Node.string(hexString)
    }
}

extension Document {
    func extractObjectId() throws -> ObjectId {
        guard let value = objectId else {
            throw ServerAbort(.notFound, reason: "objectId is required")
        }
        return value
    }
    func extractObjectId(_ key: String) throws -> ObjectId {
        guard let value = self[key] as? ObjectId  else {
            throw ServerAbort(.notFound, reason: "\(key) is required")
        }
        return value
    }
    func extractInteger(_ key: String) throws -> Int {
        guard let value = self[key]?.intValue else {
            throw ServerAbort(.notFound, reason: "\(key) is required")
        }
        return value
    }
    func extractIntegerString(_ key: String) throws -> String {
        guard let value = self[key]?.intValue, let valueString = Formatter.numberFormatter.string(for: value) else {
            throw ServerAbort(.notFound, reason: "\(key) is required")
        }
        return valueString
    }
    func extractDouble(_ key: String) throws -> Double {
        guard let value = self[key]?.doubleValue else {
            throw ServerAbort(.notFound, reason: "\(key) is required")
        }
        return value
    }
    func extractBoolean(_ key: String) throws -> Bool {
        guard let value = self[key] as? Bool else {
            throw ServerAbort(.notFound, reason: "\(key) is required")
        }
        return value
    }
    func extractString(_ key: String) throws -> String {
        guard let value = self[key] as? String, value.isEmpty == false else {
            throw ServerAbort(.notFound, reason: "\(key) is required")
        }
        return value
    }
    func extractDate(_ key: String) throws -> Date {
        guard let value = self[key] as? Date else {
            throw ServerAbort(.notFound, reason: "\(key) is required")
        }
        return value
    }
}

extension Content {
    func extract<T: NodeConvertible>(_ key: String) throws -> T {
        guard let value = self[key] else {
            throw ServerAbort(.notFound, reason: "\(key) is required")
        }
        do {
            let value = try value.get() as T
            if let stringValue = value as? String {
                guard stringValue.isEmpty == false else {
                    throw ServerAbort(.notFound, reason: "\(key) is empty")
                }
            }
            return value
        } catch {
            throw ServerAbort(.notFound, reason: "\(key) is invalid")
        }
    }
    
    func extractValidatedEmail(_ key: String) throws -> String {
        let value = try extract(key) as String
        do {
            try value.validated(by: EmailValidator())
        } catch {
            throw ServerAbort(.notFound, reason: "\(key) is invalid")
        }
        return value
    }
}

extension Parameters {
    func extract<T: NodeConvertible>(_ key: String) throws -> T {
        guard let value = self[key] else {
            throw ServerAbort(.notFound, reason: "\(key) is required")
        }
        do {
            let value = try value.get() as T
            if let stringValue = value as? String {
                guard stringValue.isEmpty == false else {
                    throw ServerAbort(.notFound, reason: "\(key) is empty")
                }
            }
            return value
        } catch {
            throw ServerAbort(.notFound, reason: "\(key) is invalid")
        }
    }
}

extension Document {
    func makeJSON() -> Cheetah.Value {
        func makeJSONValue(_ original: BSON.Primitive) -> Cheetah.Value {
            switch original {
            case let int as Int:
                return int
            case let int as Int32:
                return Int(int)
            case let double as Double:
                return double
            case let string as String:
                return string
            case let document as Document:
                return document.makeJSON()
            case let objectId as ObjectId:
                return objectId.hexString
            case let bool as Bool:
                return bool
            case let date as Date:
                return Formatter.iso8601.string(from: date)
            case let null as NSNull:
                return null
            default:
                return NSNull()
            }
        }
        
        if self.validatesAsArray() {
            return JSONArray(self.arrayRepresentation.map(makeJSONValue))
        } else {
            var object = JSONObject()
            
            for (key, value) in self {
                if key == "_id" {
                    object["id"] = makeJSONValue(value)
                } else {
                    object[key] = makeJSONValue(value)
                }
            }
            
            return object
        }
    }
    var objectId: ObjectId? {
        return self["_id"] as? ObjectId
    }
    
    func extract<T: Primitive>(_ key: String) throws -> T {
        guard let value = self[key] as? T else {
            throw ServerAbort(.notFound, reason: "\(key) is required")
        }
        return value
    }
    
    func makeResponse() throws -> Response {
        return Response(status: .ok, headers: [
            "Content-Type": "application/json; charset=utf-8"
        ], body: Body(self.makeJSON().serialize()))
    }
}

extension CollectionSlice where Element == Document {
    func makeResponse() throws -> Response {
        return Response(status: .ok, headers: [
            "Content-Type": "application/json; charset=utf-8"
        ], body: Body(self.makeDocument().makeJSON().serialize()))
    }
}

extension Response {
    convenience init(jsonStatus status: Status) {
        self.init(status: status, headers: ["Content-Type": "application/json; charset=utf-8"], body: [:].serialize())
    }
}

extension Request {
    var jsonResponse: Bool {
        return headers["Accept"]?.components(separatedBy: ",").contains("application/json") == true
    }
    
    var pageInfo: (page: Int, limit: Int, skip: Int) {
        if jsonResponse {
            return (page: 0, limit: data["limit"]?.int ?? 50, skip: data["skip"]?.int ?? 0)
        }
        let limit: Int = data["limit"]?.int ?? 15
        if let skip: Int = data["skip"]?.int {
            let page: Int = skip / limit
            return (page: page, limit: limit, skip: skip)
        } else {
            let page = (data["page"]?.int ?? 1)
            let skip = limit * (page - 1)
            return (page: page, limit: limit, skip: skip)
        }
    }
}

extension Email {
    func send() throws {
        guard let apiUrl = Admin.settings.mailgunApiUrl, let apiKey = Admin.settings.mailgunApiKey else { return }
        let request = Request(method: .post, uri: "\(apiUrl)/messages")
        let basic = "api:\(apiKey)".makeBytes().base64Encoded.makeString()
        request.headers["Authorization"] = "Basic \(basic)"
        
        var json = JSON()
        try json.set("subject", self.subject)
        switch self.body.type {
        case .html:
            try json.set("html", self.body.content)
        case .plain:
            try json.set("text", self.body.content)
        }
        
        let fromName = self.from.name ?? "Fax Server"
        let from = FormData.Field(
            name: "from",
            filename: nil,
            part: Part(
                headers: [:],
                body: "\(fromName) <\(self.from.address)>".makeBytes()
            )
        )
        
        let to = FormData.Field(
            name: "to",
            filename: nil,
            part: Part(
                headers: [:],
                body: self.to.map({ $0.address }).joined(separator: ", ").makeBytes()
            )
        )
        
        let subject = FormData.Field(
            name: "subject",
            filename: nil,
            part: Part(
                headers: [:],
                body: self.subject.makeBytes()
            )
        )
        
        let bodyKey: String
        switch self.body.type {
        case .html:
            bodyKey = "html"
        case .plain:
            bodyKey = "text"
        }
        
        let body = FormData.Field(
            name: bodyKey,
            filename: nil,
            part: Part(
                headers: [:],
                body: self.body.content.makeBytes()
            )
        )
        
        request.formData = [
            "from": from,
            "to": to,
            "subject": subject,
            bodyKey: body
        ]
        
        let response = try EngineClient.factory.respond(to: request)
        guard response.status.isValid else {
            Logger.error("Send Email Error: \(response)")
            throw Abort.badRequest
        }
    }
}

extension Node {
    func formURLEncodedPlus() throws -> Bytes {
        guard let dict = self.object else { return [] }
        
        var bytes: [[Byte]] = []
        
        for (key, val) in dict {
            var subbytes: [Byte] = []
            
            if let object = val.object {
                subbytes += object.formURLEncoded(forKey: key).makeBytes()
            } else {
                subbytes += key.urlQueryPercentEncoded.makeBytes()
                subbytes.append(.equals)
                subbytes += val.string.formURLEncodedValue().makeBytes()
            }
            
            bytes.append(subbytes)
        }
        
        return bytes.joined(separator: [Byte.ampersand]).array
    }
}

private extension Dictionary where Key == String, Value == Node {
    func formURLEncoded(forKey key: String) -> String {
        let key = key.urlQueryPercentEncoded
        let values = map { subKey, value in
            var encoded = key
            encoded += "%5B\(subKey.urlQueryPercentEncoded)%5D="
            encoded += value.string.formURLEncodedValue()
            return encoded
            } as [String]
        
        return values.joined(separator: "&")
    }
}

private extension Optional where Wrapped == String {
    func formURLEncodedValue() -> String {
        guard let value = self else { return "" }
        return value.urlQueryPercentEncodedPlus
    }
}

extension String {
    var urlQueryPercentEncodedPlus: String {
        var set = CharacterSet.urlQueryAllowed
        set.remove(charactersIn: "!$&'()*+,;=:#[]@")
        return self.addingPercentEncoding(withAllowedCharacters: set) ?? ""
    }
    var numberString: String {
        guard let number = Formatter.numberFormatter.number(from: self) else {
            return self
        }
        return Formatter.numberFormatter.string(from: number) ?? self
    }
    var intValue: Int? {
        return Formatter.numberFormatter.number(from: self)?.intValue
    }
    
    static func tokenEncoded() throws -> String {
        return try Application.shared.random.bytes(count: 30).base64EncodedString
    }
    
    static func token() throws -> String {
        return try Application.shared.random.bytes(count: 30).hexString
    }
}

extension Int {
    var seconds: Int {
        return self % 60
    }
    var minutes: Int {
        return (self / 60)
    }
    var timeString: String {
        if minutes != 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }
}

extension Primitive {
    var intValue: Int? {
        if let int = self as? Int {
            return int
        } else if let int = self as? Int32 {
            return Int(Double(int))
        } else if let double = self as? Double {
            return Int(double)
        }
        return nil
    }
    var doubleValue: Double? {
        if let double = self as? Double {
            return double
        } else if let int = self as? Int {
            return Double(int)
        } else if let int = self as? Int32 {
            return Double(int)
        }
        return nil
    }
    var numberString: String? {
        if let int = self as? Int {
            return Formatter.numberFormatter.string(for: int)
        } else if let int = self as? Int32 {
            return Formatter.numberFormatter.string(for: int)
        } else if let double = self as? Double {
            return Formatter.numberFormatter.string(for: double)
        }
        return nil
    }
    var currencyString: String? {
        if let double = doubleValue {
            return "\(double)"
        }
        if let double = self as? Double {
            return Formatter.currencyNumberFormatter.string(for: abs(double))
        } else if let int = self as? Int {
            return Formatter.currencyNumberFormatter.string(for: abs(int))
        } else if let int = self as? Int32 {
            return Formatter.currencyNumberFormatter.string(for: abs(int))
        }
        return nil
    }
}

extension Date {
    var longString: String {
        return Formatter.longFormatter.string(from: self)
    }
}

extension Formatter {
    static let longFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "E, MMM d, yyyy h:mm:ss a"
        dateFormatter.timeZone = TimeZone(identifier: Admin.settings.timeZone)
        return dateFormatter
    }()
    static let twilioIso8601: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssX"
        return formatter
    }()
    static let iso8601: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        return formatter
    }()
    static let numberFormatter: NumberFormatter = {
        let numberFormatter = NumberFormatter()
        numberFormatter.minimumSignificantDigits = 0
        return numberFormatter
    }()
    static let currencyNumberFormatter: NumberFormatter = {
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .currency
        numberFormatter.maximumFractionDigits = 4
        numberFormatter.minimumFractionDigits = 2
        return numberFormatter
    }()
}

extension StructuredDataWrapper {
    var iso8601Date: Date? {
        guard let dateString = self.string else {
            return nil
        }
        return Formatter.twilioIso8601.date(from: dateString)
    }
    
    var objectId: ObjectId? {
        guard let string = self.string else {
            return nil
        }
        return try? ObjectId(string)
    }
}
