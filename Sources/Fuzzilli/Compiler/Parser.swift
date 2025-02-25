// Copyright 2023 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Foundation

/// Parses JavaScript code into an AST.
///
/// Frontent to the node.js/babel based parser in the Parser/ subdirectory.
public class JavaScriptParser {
    public typealias AST = Compiler_Protobuf_AST

    /// The path to the node.js executable used for running the parser script.
    public let nodejsExecutablePath: String

    // Simple error enum for errors that are displayed to the user.
    public enum ParserError: Error {
        case parsingFailed(String)
    }

    /// The path to the parse.js script that implements the actual parsing using babel.js.
    private let parserScriptPath: String

    public init?() {
        guard let path = JavaScriptParser.findNodeJsInstallation() else {
            return nil
        }
        self.nodejsExecutablePath = path

        // The Parser/ subdirectory is copied verbatim into the module bundle, see Package.swift.
        self.parserScriptPath = Bundle.module.path(forResource: "parser", ofType: "js", inDirectory: "Parser")!

        // Check if the parser works. If not, it's likely because its node.js dependencies have not been installed.
        do {
            try runParserScript(withArguments: [])
        } catch {
            return nil
        }
    }

    public func parse(_ path: String) throws -> AST {
        let astProtobufDefinitionPath = Bundle.module.path(forResource: "ast", ofType: "proto")!
        let outputFilePath = FileManager.default.temporaryDirectory.path + "/" + UUID().uuidString + ".ast.proto"
        try runParserScript(withArguments: [astProtobufDefinitionPath, path, outputFilePath])
        let data = try Data(contentsOf: URL(fileURLWithPath: outputFilePath))
        try FileManager.default.removeItem(atPath: outputFilePath)
        return try AST(serializedData: data)
    }

    private func runParserScript(withArguments arguments: [String]) throws {
        let output = Pipe()
        let task = Process()
        task.standardOutput = output
        task.standardError = output
        task.arguments = [parserScriptPath] + arguments
        task.executableURL = URL(fileURLWithPath: nodejsExecutablePath)
        try task.run()
        task.waitUntilExit()

        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard task.terminationStatus == 0 else {
            throw ParserError.parsingFailed(String(data: data, encoding: .utf8)!)
        }
    }

    /// Looks for an executable named `node` in the $PATH and, if found, returns it.
    private static func findNodeJsInstallation() -> String? {
        if let pathVar = ProcessInfo.processInfo.environment["PATH"] {
            var directories = pathVar.split(separator: ":")
            // Also append the homebrew binary path since it may not be in $PATH, especially inside XCode.
            directories.append("/opt/homebrew/bin")
            for directory in directories {
                let path = String(directory + "/node")
                if FileManager.default.isExecutableFile(atPath: path) {
                    return path
                }
            }
        }
        return nil
    }
}
