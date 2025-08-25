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

import ArgumentParser
import Foundation
import HomomorphicEncryption
@testable import PIRServiceTesting
import PrivateInformationRetrieval
import Util

@main
struct PIRClientTool: AsyncParsableCommand {
    static let configuration: CommandConfiguration = .init(
        commandName: "PIRClientTool",
        abstract: "PIR Service 測試工具",
        discussion: """
        這個工具可以連接到真實的 PIR Service 並執行查詢測試。
        支援傳統 PIR 和對稱 PIR 兩種查詢方式。
        """)
    
    @Option(help: "PIR Service 的基礎 URL (例如: https://example.com 或 http://localhost:8080)")
    var baseURL: String
    
    @Option(help: "要查詢的電話號碼 (例如: +1234567890)")
    var phoneNumber: String
    
    @Option(help: "使用案例名稱 (預設: test)")
    var usecase: String = "test"
    
    @Flag(help: "使用對稱 PIR 查詢 (預設使用傳統 PIR)")
    var symmetric: Bool = false
    
    @Option(help: "使用者令牌 (用於 Privacy Pass 驗證)")
    var userToken: String?
    
    @Option(help: "平台類型 (iOS18, iOS18_2, macOS15, macOS15_2)")
    var platform: String = "iOS18"
    
    func run() async throws {
        guard let url = URL(string: baseURL) else {
            throw ValidationError("無效的 base URL: \(baseURL)")
        }
        
        let platformEnum: Platform
        switch platform.lowercased() {
        case "ios18":
            platformEnum = .iOS18
        case "ios18_2":
            platformEnum = .iOS18_2
        case "macos15":
            platformEnum = .macOS15
        case "macos15_2":
            platformEnum = .macOS15_2
        default:
            throw ValidationError("不支援的平台: \(platform). 支援的平台: iOS18, iOS18_2, macOS15, macOS15_2")
        }
        
        print("正在連接到 PIR Service: \(baseURL)")
        print("查詢電話號碼: \(phoneNumber)")
        print("使用案例: \(usecase)")
        print("查詢方式: \(symmetric ? "對稱 PIR" : "傳統 PIR")")
        if userToken != nil {
            print("使用 Privacy Pass 驗證")
        }
        print("平台: \(platform)")
        print("---")
        
        let httpClient = HTTPClient(baseURL: url)
        let keyword = Array(phoneNumber.utf8)
        
        // 實作 UInt32/UInt64 fallback 機制，類似 pir-service-example 的策略
        do {
            print("嘗試使用 UInt32 參數...")
            try await performPIRQuery(
                httpClient: httpClient,
                keyword: keyword,
                usecase: usecase,
                symmetric: symmetric,
                platform: platformEnum,
                userToken: userToken,
                scalarType: UInt32.self
            )
        } catch {
            print("UInt32 失敗: \(error)")
            print("嘗試使用 UInt64 參數...")
            
            do {
                try await performPIRQuery(
                    httpClient: httpClient,
                    keyword: keyword,
                    usecase: usecase,
                    symmetric: symmetric,
                    platform: platformEnum,
                    userToken: userToken,
                    scalarType: UInt64.self
                )
            } catch let uint64Error as PIRClientError {
                print("❌ UInt64 也失敗，PIR 客戶端錯誤:")
                handlePIRClientError(uint64Error)
                throw uint64Error
            } catch {
                print("❌ UInt64 失敗: \(error)")
                throw error
            }
        }
    }
    
    /// 處理 PIR 客戶端錯誤的通用方法
    private func handlePIRClientError(_ error: PIRClientError) {
        switch error {
        case .serverError(let status, let message):
            print("伺服器錯誤 (\(status)): \(message)")
        case .missingConfiguration:
            print("缺少配置，請確認使用案例名稱是否正確")
        case .missingSecretKey(let hash):
            print("缺少密鑰 (hash: \(hash.map { String(format: "%02x", $0) }.joined()))")
        case .failedToFetchToken(let status, let message):
            print("獲取令牌失敗 (\(status)): \(message)")
        case .failedToFetchTokenPublicKey(let status, let message):
            print("獲取令牌公鑰失敗 (\(status)): \(message)")
        default:
            print("\(error)")
        }
    }
}

/// 通用的 PIR 查詢執行函數，支援泛型 scalar type
private func performPIRQuery<T: ScalarType>(
    httpClient: HTTPClient,
    keyword: [UInt8],
    usecase: String,
    symmetric: Bool,
    platform: Platform,
    userToken: String?,
    scalarType: T.Type
) async throws {
    var pirClient = PIRClient<MulPirClient<Bfv<T>>>(
        connection: httpClient,
        platform: platform,
        userToken: userToken
    )
    
    print("正在獲取配置...")
    
    // 先嘗試取得配置來檢查連接和參數兼容性
    if pirClient.configCache[usecase] == nil {
        do {
            try await pirClient.rotateKey(for: usecase)
            print("✅ 成功獲取配置 (使用 \(T.self) 參數)")
        } catch {
            print("❌ 獲取配置失敗: \(error)")
            throw error
        }
    }
    
    print("正在執行查詢...")
    print("[DEBUG] 開始 \(symmetric ? "對稱 PIR" : "傳統 PIR") 查詢 (使用 \(T.self) 參數)")
    let result: [KeywordValuePair.Value?]
    
    if symmetric {
        result = try await pirClient.symmetricPirRequest(
            keywords: [keyword],
            usecase: usecase,
            allowKeyRotation: false
        )
    } else {
        result = try await pirClient.request(
            keywords: [keyword],
            usecase: usecase,
            allowKeyRotation: false
        )
    }
    
    print("[DEBUG] 查詢完成，收到 \(result.count) 個結果")
    
    if let value = result.first {
        if let value = value {
            let resultString = String(data: Data(value), encoding: .utf8) ?? 
                "<\(value.count) bytes 的二進制回應>"
            print("✅ 查詢成功！(使用 \(T.self) 參數)")
            print("結果: \(resultString)")
        } else {
            print("❌ 查詢成功，但沒有找到該電話號碼的資料")
        }
    } else {
        print("❌ 查詢失敗：沒有回應")
    }
}