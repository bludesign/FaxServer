//
//  Logger.swift
//  Server
//
//  Created by BluDesign, LLC on 4/1/17.
//

import Foundation

struct Logger {
    
    // MARK: - Enums
    
    enum Level {
        case verbose
        case debug
        case info
        case warning
        case error
        case severe
        case none
        
        public var description: String {
            switch self {
            case .verbose:
                return "🆗 VERBOSE"
            case .debug:
                return "❎ DEBUG"
            case .info:
                return "🚹 INFO"
            case .warning:
                return "⚠️ WARNING"
            case .error:
                return "⛔️ ERROR"
            case .severe:
                return "📛 SEVERE"
            case .none:
                return "NONE"
            }
        }
        
        public static let all: [Level] = [.verbose, .debug, .info, .warning, .error, .severe]
    }
    
    typealias Log = (level: Logger.Level, date: Date, file: String?, message: String)
    
    // MARK: - Parameters
    
    static var logging: Bool = true
    
    // MARK: - Methods
    
    static func verbose(_ message: String, functionName: String = #function, fileName: String = #file, lineNumber: Int = #line) {
        Logger.logln(level: .verbose, functionName: functionName, fileName: fileName, lineNumber: lineNumber, message: message)
    }
    
    static func info(_ message: String, functionName: String = #function, fileName: String = #file, lineNumber: Int = #line) {
        Logger.logln(level: .info, functionName: functionName, fileName: fileName, lineNumber: lineNumber, message: message)
    }
    
    static func debug(_ message: String, functionName: String = #function, fileName: String = #file, lineNumber: Int = #line) {
        Logger.logln(level: .debug, functionName: functionName, fileName: fileName, lineNumber: lineNumber, message: message)
    }
    
    static func warning(_ message: String, functionName: String = #function, fileName: String = #file, lineNumber: Int = #line) {
        Logger.logln(level: .warning, functionName: functionName, fileName: fileName, lineNumber: lineNumber, message: message)
    }
    
    static func error(_ message: String, functionName: String = #function, fileName: String = #file, lineNumber: Int = #line) {
        Logger.logln(level: .error, functionName: functionName, fileName: fileName, lineNumber: lineNumber, message: message)
    }
    
    static func severe(_ message: String, functionName: String = #function, fileName: String = #file, lineNumber: Int = #line) {
        Logger.logln(level: .severe, functionName: functionName, fileName: fileName, lineNumber: lineNumber, message: message)
    }
    
    static func logln(level: Level, functionName: String = #function, fileName: String = #file, lineNumber: Int = #line, message: String) {
        if logging {
            let fileName = URL(fileURLWithPath: fileName)
            let file = "\(fileName.lastPathComponent).\(functionName):\(lineNumber)"
            print("\(level.description) \(file) - \(message)")
        }
    }
}
