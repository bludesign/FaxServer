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
import Multipart
import Crypto
import Validation
import Leaf

extension URL {
    var fullHost: String {
        if let host = host {
            return host
        } else {
            return absoluteString
        }
    }
}

extension HTTPRequest {
    var hostUrl: URL? {
        guard let header = headers["Host"].first else { return nil }
        if header.hasPrefix("http") {
            return URL(string: header)
        } else {
            return URL(string: "http://\(header)")
        }
    }
}

extension ObjectId: Parameter {
    /// Attempts to read the parameter into a `UUID`
    public static func resolveParameter(_ parameter: String, on container: Container) throws -> ObjectId {
        return try ObjectId(parameter)
    }
}

enum ServerResponse: ResponseEncodable {
    func encode(for request: Request) throws -> Future<Response> {
        switch self {
        case .string(let string):
            return try string.encode(for: request)
        case .response(let response):
            return try response.encode(for: request)
        case .view(let view):
            return try view.encode(for: request)
        }
    }
    
    case string(String)
    case response(Response)
    case view(View)
}

extension Optional {
    func unwrapped(_ name: String) throws -> Wrapped {
        switch self {
        case .none:
            throw ServerAbort(.badRequest, reason: "\(name) is required")
        case .some(let value):
            return value
        }
    }
}

extension EventLoopPromise where T == ServerResponse {
    func submit(_ futureResponse: Future<ServerResponse>) {
        futureResponse.do { serverResponse in
            self.succeed(result: serverResponse)
            }.catch { error in
                self.fail(error: error)
        }
    }
}

extension Request {
    func globalAsync(block: @escaping (_: EventLoopPromise<ServerResponse>) throws -> Swift.Void) -> EventLoopFuture<ServerResponse> {
        let promise = eventLoop.newPromise(ServerResponse.self)
        DispatchQueue.global().async {
            do {
                try block(promise)
            } catch let error {
                promise.fail(error: error)
            }
        }
        return promise.futureResult
    }
    
    func get<D>(_ type: D.Type = D.self, at keyPath: BasicKeyRepresentable...) throws -> D where D: Decodable {
        if let value = try? query.get(D.self, at: keyPath) as D {
            return value
        } else if let value = try? content.syncGet(D.self, at: keyPath) as D {
            return value
        } else {
            throw ServerAbort(.badRequest, reason: "\(keyPath) not found")
        }
    }
    
    func statusRedirectEncoded(status: HTTPStatus, to location: String, type: RedirectType = .normal) throws -> Future<ServerResponse> {
        if jsonResponse {
            return try statusEncoded(status: status)
        }
        return try redirectEncoded(to: location, type: type)
    }
    
    func serverRedirect(to location: String, type: RedirectType = .normal) -> ServerResponse {
        return ServerResponse.response(redirect(to: location, type: type))
    }
    
    func redirectEncoded(to location: String, type: RedirectType = .normal) throws -> Future<ServerResponse> {
        return try redirect(to: location, type: type).encode(for: self).map(to: ServerResponse.self) { response in
            return ServerResponse.response(response)
        }
    }
    
    func serverStatusRedirect(status: HTTPStatus, to location: String, type: RedirectType = .normal) -> ServerResponse {
        if jsonResponse {
            return ServerResponse.response(statusResponse(status: status))
        }
        return ServerResponse.response(redirect(to: location, type: type))
    }
    
    func serverStatus(status: HTTPStatus) -> ServerResponse {
        return ServerResponse.response(statusResponse(status: status))
    }
    
    func statusEncoded(status: HTTPStatus) throws -> Future<ServerResponse> {
        if jsonResponse {
            return try statusResponse(status: status).encode(for: self).map(to: ServerResponse.self) { response in
                return ServerResponse.response(response)
            }
        } else {
            let context: [String: String] = [
                "errorCode": String(status.code),
                "errorTitle": status.reasonPhrase
            ]
            return try renderEncoded("error", context)
        }
    }
    
    func statusResponse(status: HTTPStatus) -> Response {
        let response = Response(using: sharedContainer)
        response.http.headers.replaceOrAdd(name: .contentType, value: "application/json")
        response.http.status = status
        response.http.body = HTTPBody(string: "{}")
        return response
    }
    
    func rawJsonResponse(body: HTTPBody) -> Response {
        let response = Response(using: sharedContainer)
        response.http.headers.replaceOrAdd(name: .contentType, value: "application/json")
        response.http.status = .ok
        response.http.body = body
        return response
    }
    
    // JSON Encoding
    
    func makeJsonResponse<T>(_ jsonObject: T, status: HTTPResponseStatus = .ok) throws -> Response where T : Encodable {
        let response = Response(using: sharedContainer)
        response.http.headers.replaceOrAdd(name: .contentType, value: "application/json")
        response.http.body = try HTTPBody(data: JSONEncoder().encode(jsonObject))
        response.http.status = status
        return response
    }
    
    func makeJsonResponse(_ data: Data, status: HTTPResponseStatus = .ok) -> Response {
        let response = Response(using: sharedContainer)
        response.http.headers.replaceOrAdd(name: .contentType, value: "application/json")
        response.http.body = HTTPBody(data: data)
        response.http.status = status
        return response
    }
    
    func jsonEncoded(json: [String: Codable], type: RedirectType = .normal) throws -> Future<ServerResponse> {
        let response = Response(using: sharedContainer)
        response.http.headers.replaceOrAdd(name: .contentType, value: "application/json")
        response.http.status = .ok
        response.http.body = try HTTPBody(data: JSONSerialization.data(withJSONObject: json, options: JSONSerialization.WritingOptions(rawValue: 0)))
        return try response.encode(for: self).map(to: ServerResponse.self) { response in
            return ServerResponse.response(response)
        }
    }
    
    // Leaf Encoding
    
    func renderEncoded(_ path: String, _ context: TemplateData) throws -> Future<ServerResponse> {
        return try make(LeafRenderer.self).render(path, context).map(to: ServerResponse.self) { view in
            return ServerResponse.view(view)
        }
    }
    
    func renderEncoded<E>(_ path: String, _ context: E) throws -> Future<ServerResponse> where E: Encodable {
        return try make(LeafRenderer.self).render(path, context).map(to: ServerResponse.self) { view in
            return ServerResponse.view(view)
        }
    }
}

extension Content {
    func encoded(request: Request) throws -> Future<ServerResponse> {
        return try encode(for: request).map(to: ServerResponse.self) { response in
            return ServerResponse.response(response)
        }
    }
}

extension String {
    var url: URL? {
        return URL(string: self)
    }
    
    var isHiddenText: Bool {
        return self == Constants.hiddenText
    }
    
    var base64Decoded: String? {
        guard let data = Data(base64Encoded: self) else { return nil }
        return String(data: data, encoding: .utf8)
    }
    
    func urlEncodedFormEncoded() throws -> String {
        var allowedCharacters = CharacterSet.urlQueryAllowed
        allowedCharacters.remove("+")
        allowedCharacters.remove("'")
        guard let string = self.addingPercentEncoding(withAllowedCharacters: allowedCharacters) else {
            throw URLEncodedFormError(identifier: "percentEncoding", reason: "Failed to percent encode string: \(self)")
        }
        return string
    }
    
    var doubleValue: Double? {
        return Double(self)
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
    func extractUserPermission(_ key: String) throws -> User.Permission {
        let value = try self.extractInteger("permission")
        guard let permission = User.Permission(rawValue: value) else {
            throw ServerAbort(.notFound, reason: "Invalid permission")
        }
        return permission
    }
    
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
    
    func makeResponse(_ request: Request) throws -> EventLoopFuture<ServerResponse> {
        let response = Response(using: request.sharedContainer)
        response.http.headers.replaceOrAdd(name: .contentType, value: "application/json; charset=utf-8")
        response.http.body = HTTPBody(data: self.makeJSON().serialize().convertToData())
        response.http.status = .ok
        return try response.encode(for: request).map(to: ServerResponse.self) { mappedResponse in
            return ServerResponse.response(mappedResponse)
        }
    }
}

extension CollectionSlice where Element == Document {
    func makeResponse(_ request: Request) throws -> EventLoopFuture<ServerResponse> {
        let response = Response(using: request.sharedContainer)
        response.http.headers.replaceOrAdd(name: .contentType, value: "application/json; charset=utf-8")
        response.http.body = HTTPBody(data: self.makeDocument().makeJSON().serialize().convertToData())
        response.http.status = .ok
        return try response.encode(for: request).map(to: ServerResponse.self) { mappedResponse in
            return ServerResponse.response(mappedResponse)
        }
    }
}

extension Request {
    struct PageInfo {
        let page: Int
        let skip: Int
        let limit: Int
    }
    
    private struct InternalPageInfo: Codable {
        var page: Int?
        var skip: Int?
        var limit: Int?
    }
    
    var pageInfo: PageInfo {
        let pageInfo = (try? query.decode(InternalPageInfo.self)) ?? InternalPageInfo()
        if jsonResponse {
            return PageInfo(page: 0, skip: pageInfo.skip ?? 0, limit: pageInfo.limit ?? 100)
        }
        let limit = pageInfo.limit ?? 20
        if let skip = pageInfo.skip {
            let page = skip / limit
            return PageInfo(page: page, skip: skip, limit: limit)
        } else {
            let page = pageInfo.page ?? 1
            let skip = limit * (page - 1)
            return PageInfo(page: page, skip: skip, limit: limit)
        }
    }
    
    func checkAdmin(_ redirect: String) throws {
        
    }
    
    var jsonResponse: Bool {
        return http.headers["Accept"].first?.components(separatedBy: ",").contains("application/json") == true
    }
}

struct Email {
    static func send(subject: String, to: String, htmlBody: Data, redirect: String?, request: Request, promise: EventLoopPromise<ServerResponse>?) throws {
        guard let apiUrl = Admin.settings.mailgunApiUrl, let apiKey = Admin.settings.mailgunApiKey else {
            throw ServerAbort(.internalServerError, reason: "MailGun not setup")
        }
        struct FormData: Content {
            var from: String?
            var to: String?
            var subject: String?
            var html: String?
        }
        var formData = FormData()
        formData.from = "Fax Server <\(Admin.settings.mailgunFromEmail)>"
        formData.to = to
        formData.subject = subject
        guard let htmlBodyString = String(data: htmlBody, encoding: .utf8) else {
            throw ServerAbort(.internalServerError, reason: "Error creating email body")
        }
        formData.html = htmlBodyString
        
        guard let basic = "api:\(apiKey)".data(using: .utf8)?.base64EncodedString() else {
            throw ServerAbort(.internalServerError, reason: "Error creating Mailgun login")
        }
        let requestClient = try request.make(Client.self)
        let headers = HTTPHeaders([
            ("Authorization", "Basic \(basic)"),
            ("Accept", "application/json")
        ])
        requestClient.post("\(apiUrl)/messages", headers: headers, beforeSend: { request in
            try request.content.encode(formData, as: MediaType.urlEncodedForm)
        }).do { response in
            guard let promise = promise else { return }
            guard response.http.status.isValid else {
                return promise.fail(error: ServerAbort(response.http.status, reason: "Mailgun reponse error"))
            }
            if let redirect = redirect, request.jsonResponse == false {
                return promise.succeed(result: ServerResponse.response(request.redirect(to: redirect)))
            }
            return promise.succeed(result: ServerResponse.response(response))
        }.catch { error in
            return promise?.fail(error: error)
        }
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
        return try MainApplication.shared.random.generateData(count: 30).base64EncodedString()
    }
    
    static func token() throws -> String {
        return try MainApplication.shared.random.generateData(count: 30).hexEncodedString()
    }
    
    var collapseWhitespace: String {
        let theComponents = components(separatedBy: NSCharacterSet.whitespacesAndNewlines).filter { !$0.isEmpty }
        return theComponents.joined(separator: " ")
    }
    
    func isValidEmail() -> Bool {
        #if os(Linux) && !swift(>=3.1)
        let regex = try? RegularExpression(pattern: "^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$", options: .caseInsensitive)
        #else
        let regex = try? NSRegularExpression(pattern: "^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$", options: .caseInsensitive)
        #endif
        return regex?.firstMatch(in: self, options: [], range: NSMakeRange(0, self.count)) != nil
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
