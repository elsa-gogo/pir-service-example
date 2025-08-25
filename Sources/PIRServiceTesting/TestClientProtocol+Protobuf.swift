// Copyright 2024 Apple Inc. and the Swift Homomorphic Encryption project authors
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
import HummingbirdTesting
import PrivateInformationRetrievalProtobuf
import SwiftProtobuf

extension TestClientProtocol {
    func post(path: String, body: [UInt8], headers: HTTPFields) async throws -> TestResponse {
        try await executeRequest(uri: path, method: .post, headers: headers, body: .init(bytes: body))
    }

    func get(path: String, body: [UInt8], headers: HTTPFields) async throws -> TestResponse {
        try await executeRequest(uri: path, method: .get, headers: headers, body: .init(bytes: body))
    }

    func post<Response: Message>(path: String, body: some Message, headers: HTTPFields) async throws -> Response {
        let response = try await executeRequest(
            uri: path,
            method: .post,
            headers: headers,
            body: .init(data: body.serializedBytes()))
        guard response.status == .ok else {
            throw PIRClientError.serverError(
                status: response.status,
                message: String(data: Data(buffer: response.body), encoding: .utf8) ??
                    "<\(response.body.readableBytes) bytes of binary response>")
        }

        do {
            let responseBytes = Array(buffer: response.body)

            // Debug: Print raw response information
            print("[DEBUG] Raw response for \(path):")
            print("[DEBUG] Response size: \(responseBytes.count) bytes")

            let parsedResponse = try Response(serializedBytes: responseBytes)

            // Debug: Print parsed protobuf response if it's Apple_SwiftHomomorphicEncryption_Api_Pir_V1_Responses
            if let responses = parsedResponse as? Apple_SwiftHomomorphicEncryption_Api_Pir_V1_Responses {
                print("[DEBUG] Parsed Apple_SwiftHomomorphicEncryption_Api_Pir_V1_Responses:")
                print("[DEBUG] Number of responses: \(responses.responses.count)")
                for (index, response) in responses.responses.enumerated() {
                    print("[DEBUG] Response[\(index)]:")
                    switch response.response {
                    case .pirResponse(let pirResponse):
                        print("[DEBUG] Response[\(index)]: has PIR response with \(pirResponse.replies.count) replies")

                        // Print detailed ciphertext information
                        for (replyIndex, reply) in pirResponse.replies.enumerated() {
                            print("[DEBUG] Response[\(index)]: Reply[\(replyIndex)]: \(reply.ciphertexts.count) ciphertexts")
                            for (ctIndex, ciphertext) in reply.ciphertexts.enumerated() {
                                switch ciphertext.serializedCiphertextType {
                                case .seeded(let seededCt):
                                    print("[DEBUG] Response[\(index)]: Reply[\(replyIndex)]: CT[\(ctIndex)]: SEEDED - poly0=\(seededCt.poly0.count)bytes, seed=\(seededCt.seed.count)bytes")
                                case .full(let fullCt):
                                    print("[DEBUG] Response[\(index)]: Reply[\(replyIndex)]: CT[\(ctIndex)]: FULL - polys=\(fullCt.polys.count)bytes, skipLsbs=\(fullCt.skipLsbs)")
                                case .none:
                                    print("[DEBUG] Response[\(index)]: Reply[\(replyIndex)]: CT[\(ctIndex)]: EMPTY")
                                }
                            }
                        }

                        // Print stash information
                        if !pirResponse.stash.hashedKeywords.isEmpty {
                            print("[DEBUG] Response[\(index)]: stash has \(pirResponse.stash.hashedKeywords.count) hashed keywords")
                            print("[DEBUG] Response[\(index)]: stash hashed keywords: \(pirResponse.stash.hashedKeywords.map { String(format: "%016x", $0) })")
                            print("[DEBUG] Response[\(index)]: stash values: \(pirResponse.stash.values.enumerated().map { "[\($0.offset)]:\($0.element.count)bytes" })")
                            if !pirResponse.stash.removedHashedKeywords.isEmpty {
                                print("[DEBUG] Response[\(index)]: stash removed keywords: \(pirResponse.stash.removedHashedKeywords.map { String(format: "%016x", $0) })")
                            }
                        }
                    case .oprfResponse(let oprfResponse):
                        print("[DEBUG] Response[\(index)]: has OPRF response with \(oprfResponse.evaluatedElement.count) bytes evaluated element")
                        print("[DEBUG] Response[\(index)]: OPRF evaluated element: \(oprfResponse.evaluatedElement.prefix(32).map { String(format: "%02x", $0) }.joined(separator: " "))...")
                        print("[DEBUG] Response[\(index)]: OPRF proof: \(oprfResponse.proof.count) bytes - \(oprfResponse.proof.prefix(32).map { String(format: "%02x", $0) }.joined(separator: " "))...")
                    case .none:
                        print("[DEBUG] Response[\(index)]: has no response")
                    }
                }
            }

            return parsedResponse
        } catch {
            print("[DEBUG] Failed to parse protobuf response for \(path): \(error)")
            let errorResponseBytes = Array(buffer: response.body)
            print("[DEBUG] Complete error response bytes: \(errorResponseBytes.map { String(format: "%02x", $0) }.joined(separator: " "))")
            throw error
        }
    }
}

extension HTTPField.Name {
    // swiftlint:disable:next force_unwrapping
    static var userIdentifier: Self { Self("User-Identifier")! }
}
