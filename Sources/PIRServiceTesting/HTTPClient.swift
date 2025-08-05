// Copyright 2024-2025 Apple Inc. and the Swift Homomorphic Encryption project authors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Foundation
import HTTPTypes
@testable import HummingbirdTesting
import NIOCore
#if !canImport(Darwin)
import NIOFoundationCompat
#endif

public struct HTTPClient: TestClientProtocol {
    private let baseURL: URL
    private let urlSession: URLSession
    
    public var port: Int? {
        baseURL.port
    }
    
    public init(baseURL: URL, urlSession: URLSession = .shared) {
        self.baseURL = baseURL
        self.urlSession = urlSession
    }
    
    public func executeRequest(
        uri: String,
        method: HTTPRequest.Method,
        headers: HTTPFields,
        body: ByteBuffer?
    ) async throws -> TestResponse {
        guard let url = URL(string: uri, relativeTo: baseURL) else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        
        for header in headers {
            request.setValue(header.value, forHTTPHeaderField: header.name.rawName)
        }
        
        if let body = body {
            request.httpBody = Data(buffer: body)
        }
        
        let (data, response) = try await urlSession.data(for: request)
        
        // Optional debug logging (comment out for production)
        // print("HTTP Request: \(method.rawValue) \(url)")
        // if let httpResponse = response as? HTTPURLResponse {
        //     print("HTTP Response: \(httpResponse.statusCode)")
        //     print("Response data size: \(data.count) bytes")
        // }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        let status = HTTPResponse.Status(code: httpResponse.statusCode)
        let responseHeaders = HTTPFields(httpResponse.allHeaderFields.compactMap { key, value in
            guard let name = key as? String,
                  let value = value as? String,
                  let fieldName = HTTPField.Name(name) else {
                return nil
            }
            return HTTPField(name: fieldName, value: value)
        })
        
        let httpResponseHead = HTTPResponse(status: status, headerFields: responseHeaders)
        let responseBody = ByteBuffer(data: data)
        return TestResponse(
            head: httpResponseHead,
            body: responseBody,
            trailerHeaders: nil
        )
    }
}