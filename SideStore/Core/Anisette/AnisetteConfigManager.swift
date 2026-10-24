//  AnisetteConfigManager.swift
//  SideStore
//
//  Created by Magesh K on 31/7/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation
import AnisetteKit
import SideSign

public struct AnisetteConfig: Codable, Equatable {
    public var clientInfo: String
    public var userAgent: String
    public var customDeviceID: String?
    public var customLocalUserID: String?
    public var customLocale: String?
    public var customTimeZone: String?
    public var customXcodeVersion: String?
    public var customSerialNumber: String?
    public var customRoutingInfo: String?
    
    public init(
        clientInfo: String,
        userAgent: String,
        customDeviceID: String? = nil,
        customLocalUserID: String? = nil,
        customLocale: String? = nil,
        customTimeZone: String? = nil,
        customXcodeVersion: String? = nil,
        customSerialNumber: String? = nil,
        customRoutingInfo: String? = nil
    ) {
        self.clientInfo = clientInfo
        self.userAgent = userAgent
        self.customDeviceID = customDeviceID
        self.customLocalUserID = customLocalUserID
        self.customLocale = customLocale
        self.customTimeZone = customTimeZone
        self.customXcodeVersion = customXcodeVersion
        self.customSerialNumber = customSerialNumber
        self.customRoutingInfo = customRoutingInfo
    }
}

public actor AnisetteConfigManager {
    public static let shared = AnisetteConfigManager()
    
    public nonisolated var anisetteIdentifier: String? {
        get { Keychain.shared.identifier }
        set { Keychain.shared.identifier = newValue }
    }
    
    public nonisolated var anisetteAdiBlob: String? {
        get { Keychain.shared.adiPb }
        set { Keychain.shared.adiPb = newValue }
    }
    
    public func resolveDeviceIdentifier() -> UUID {
        if let storedId = anisetteIdentifier, !storedId.isEmpty {
            if let parsed = UUID(uuidString: storedId) {
                return parsed
            }
            if let data = Data(base64Encoded: storedId), data.count == 16 {
                let uuid = data.withUnsafeBytes { UUID(uuid: $0.load(as: uuid_t.self)) }
                return uuid
            }
        }
        let generated = UUID()
        anisetteIdentifier = generated.uuidString
        return generated
    }
    
    private nonisolated var configFileURL: URL {
        let libraryDirectory = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
        return libraryDirectory.appendingPathComponent("anisette-config.json")
    }
    
    private nonisolated var serverHeadersFileURL: URL {
        let libraryDirectory = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
        return libraryDirectory.appendingPathComponent("anisette-server-headers.json")
    }
    
    public func saveServerHeaders(_ headers: [String: String]) {
        var existing = loadServerHeaders()
        for (key, val) in headers {
            existing[key] = val
        }
        let encoder = Foundation.JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(existing) {
            try? data.write(to: serverHeadersFileURL, options: .atomic)
        }
    }
    
    public nonisolated func loadServerHeaders() -> [String: String] {
        if let data = try? Data(contentsOf: serverHeadersFileURL),
           let headers = try? Foundation.JSONDecoder().decode([String: String].self, from: data) {
            return headers
        }
        return [:]
    }
    
    public nonisolated var isOfflineMode: Bool {
        get {
            UserDefaults.standard.isAnisetteOfflineMode
        }
        set {
            UserDefaults.standard.isAnisetteOfflineMode = newValue
        }
    }
    
    public func loadConfig() -> AnisetteConfig {
        let ud = UserDefaults.standard
        let udClientInfo   = ud.customAnisetteClientInfo
        let udUserAgent    = ud.customAnisetteUserAgent
        let udDeviceID     = ud.customAnisetteDeviceID
        let udLocalUserID  = ud.customAnisetteLocalUserID
        let udLocale       = ud.customAnisetteLocale
        let udTimeZone     = ud.customAnisetteTimeZone
        let udXcodeVersion = ud.customAnisetteXcodeVersion
        let udSerialNumber = ud.customAnisetteSerialNumber
        let udRoutingInfo  = ud.customAnisetteRoutingInfo

        let fileConfig: AnisetteConfig? = {
            guard let data = try? Data(contentsOf: configFileURL),
                  let config = try? Foundation.JSONDecoder().decode(AnisetteConfig.self, from: data) else {
                return nil
            }
            return config
        }()

        let serverHeaders = loadServerHeaders()
        let serverClientInfo = serverHeaders["client_info"] ?? serverHeaders["clientInfo"] ?? serverHeaders["X-MMe-Client-Info"] ?? serverHeaders["X-Mme-Client-Info"]
        let serverUserAgent = serverHeaders["user_agent"] ?? serverHeaders["userAgent"] ?? serverHeaders["User-Agent"]
        let serverRoutingInfo = serverHeaders["X-Apple-I-MD-RINFO"] ?? serverHeaders["routingInfo"] ?? serverHeaders["customRoutingInfo"]

        let rawClientInfo = (udClientInfo?.isEmpty == false ? udClientInfo : fileConfig?.clientInfo)
        var resolvedClientInfo = Self.normalizedClientInfo(rawClientInfo)
        if resolvedClientInfo.isEmpty {
            resolvedClientInfo = Self.normalizedClientInfo(serverClientInfo)
        }
        if resolvedClientInfo.isEmpty {
            resolvedClientInfo = AppConstants.Anisette.defaultClientInfo
        }

        let rawUserAgent = (udUserAgent?.isEmpty == false ? udUserAgent : fileConfig?.userAgent)?.trimmingCharacters(in: .whitespacesAndNewlines)
        var resolvedUserAgent = rawUserAgent ?? ""
        if resolvedUserAgent.isEmpty {
            resolvedUserAgent = serverUserAgent?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        if resolvedUserAgent.isEmpty {
            resolvedUserAgent = AppConstants.Anisette.defaultUserAgent
        }

        let resolvedDeviceID     = (udDeviceID?.isEmpty == false ? udDeviceID : fileConfig?.customDeviceID)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedLocalUserID  = (udLocalUserID?.isEmpty == false ? udLocalUserID : fileConfig?.customLocalUserID)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedLocale       = (udLocale?.isEmpty == false ? udLocale : fileConfig?.customLocale)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTimeZone     = (udTimeZone?.isEmpty == false ? udTimeZone : fileConfig?.customTimeZone)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedXcode        = (udXcodeVersion?.isEmpty == false ? udXcodeVersion : fileConfig?.customXcodeVersion)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedSerialNumber = (udSerialNumber?.isEmpty == false ? udSerialNumber : fileConfig?.customSerialNumber)?.trimmingCharacters(in: .whitespacesAndNewlines)
        
        let rawRoutingInfo = (udRoutingInfo?.isEmpty == false ? udRoutingInfo : fileConfig?.customRoutingInfo)?.trimmingCharacters(in: .whitespacesAndNewlines)
        var resolvedRoutingInfo  = (rawRoutingInfo?.isEmpty == false ? rawRoutingInfo : serverRoutingInfo?.trimmingCharacters(in: .whitespacesAndNewlines))
        if resolvedRoutingInfo == nil || resolvedRoutingInfo?.isEmpty == true {
            resolvedRoutingInfo = "33883392"
        }

        return AnisetteConfig(
            clientInfo: resolvedClientInfo,
            userAgent: resolvedUserAgent,
            customDeviceID: resolvedDeviceID,
            customLocalUserID: resolvedLocalUserID,
            customLocale: resolvedLocale,
            customTimeZone: resolvedTimeZone,
            customXcodeVersion: resolvedXcode,
            customSerialNumber: resolvedSerialNumber,
            customRoutingInfo: resolvedRoutingInfo
        )
    }

    /// Trims whitespaces and sanitizes client info without hardcoding or rejecting valid OS profiles
    public static func normalizedClientInfo(_ clientInfo: String?) -> String {
        guard let clientInfo = clientInfo else { return "" }
        var trimmed = clientInfo.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return ""
        }
        if trimmed.contains("com.apple.dt.Xcode") {
            trimmed = trimmed.replacingOccurrences(of: "com.apple.dt.Xcode", with: "com.apple.akd")
        }
        return trimmed
    }

    public func makeRequestHeaders() -> AnisetteRequestHeaders {
        let config = loadConfig()
        let resolvedDevID = (config.customDeviceID?.isEmpty == false ? config.customDeviceID : nil) ?? resolveDeviceIdentifier().uuidString.uppercased()
        let resolvedLU = (config.customLocalUserID?.isEmpty == false ? config.customLocalUserID : nil) ?? Data(resolvedDevID.utf8).base64EncodedString()
        let resolvedRinfo = (config.customRoutingInfo?.isEmpty == false ? config.customRoutingInfo : nil) ?? "33883392"
        return AnisetteRequestHeaders().with {
            $0.clientInfo = config.clientInfo.isEmpty ? AppConstants.Anisette.defaultClientInfo : config.clientInfo
            $0.userAgent  = config.userAgent.isEmpty ? AppConstants.Anisette.defaultUserAgent : config.userAgent
            $0.deviceID = resolvedDevID
            $0.localUserID = resolvedLU
            $0.routingInfo = resolvedRinfo
            if let loc = config.customLocale, !loc.isEmpty { $0.locale = loc }
            if let tz = config.customTimeZone, !tz.isEmpty { $0.timeZone = tz }
            if let serial = config.customSerialNumber, !serial.isEmpty { $0.serialNumber = serial }
        }
    }

    public func resolvedXcodeVersion() async -> String {
        return loadConfig().customXcodeVersion ?? "26.0 (26A242)"
    }
    
    public func saveConfig(_ config: AnisetteConfig) {
        let encoder = Foundation.JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(config) {
            try? data.write(to: configFileURL, options: .atomic)
        }
        let ud = UserDefaults.standard
        ud.customAnisetteClientInfo   = config.clientInfo
        ud.customAnisetteUserAgent    = config.userAgent
        ud.customAnisetteDeviceID     = config.customDeviceID
        ud.customAnisetteLocalUserID  = config.customLocalUserID
        ud.customAnisetteLocale       = config.customLocale
        ud.customAnisetteTimeZone     = config.customTimeZone
        ud.customAnisetteXcodeVersion = config.customXcodeVersion
        ud.customAnisetteSerialNumber = config.customSerialNumber
        ud.customAnisetteRoutingInfo  = config.customRoutingInfo
    }
    
    public func importFromFile(url: URL) throws -> AnisetteConfig {
        let data = try Data(contentsOf: url)
        
        // Flexible decoding supporting both camelCase and snake_case
        let config: AnisetteConfig
        if let direct = try? Foundation.JSONDecoder().decode(AnisetteConfig.self, from: data) {
            config = direct
        } else {
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let json = json else {
                throw NSError(domain: "AnisetteConfigManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON format."])
            }
            
            let clientInfo = (json["clientInfo"] as? String) ?? (json["client_info"] as? String)
            let userAgent = (json["userAgent"] as? String) ?? (json["user_agent"] as? String)
            
            let customDeviceID = (json["customDeviceID"] as? String) ?? (json["custom_device_id"] as? String) ?? (json["deviceUniqueIdentifier"] as? String)
            let customLocalUserID = (json["customLocalUserID"] as? String) ?? (json["custom_local_user_id"] as? String) ?? (json["localUserID"] as? String)
            let customLocale = (json["customLocale"] as? String) ?? (json["custom_locale"] as? String) ?? (json["locale"] as? String)
            let customTimeZone = (json["customTimeZone"] as? String) ?? (json["custom_time_zone"] as? String) ?? (json["timeZone"] as? String)
            
            let customSerialNumber = (json["customSerialNumber"] as? String) ?? (json["custom_serial_number"] as? String) ?? (json["serialNumber"] as? String)
            let customRoutingInfo = (json["customRoutingInfo"] as? String) ?? (json["custom_routing_info"] as? String) ?? (json["routingInfo"] as? String)
            let customXcodeVersion = (json["customXcodeVersion"] as? String) ?? (json["custom_xcode_version"] as? String) ?? (json["xcodeVersion"] as? String)
            
            guard let finalClientInfo = clientInfo, !finalClientInfo.isEmpty,
                  let finalUserAgent = userAgent, !finalUserAgent.isEmpty else {
                throw NSError(domain: "AnisetteConfigManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "Missing or empty required keys (clientInfo, userAgent)."])
            }
            
            config = AnisetteConfig(
                clientInfo: finalClientInfo,
                userAgent: finalUserAgent,
                customDeviceID: customDeviceID,
                customLocalUserID: customLocalUserID,
                customLocale: customLocale,
                customTimeZone: customTimeZone,
                customXcodeVersion: customXcodeVersion,
                customSerialNumber: customSerialNumber,
                customRoutingInfo: customRoutingInfo
            )
        }
        
        saveConfig(config)
        return config
    }
    
    public func exportConfigData() -> Data? {
        let config = loadConfig()
        let encoder = Foundation.JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        return try? encoder.encode(config)
    }
    
    @discardableResult
    public nonisolated func resetToDefaults() -> AnisetteConfig {
        let ud = UserDefaults.standard
        ud.customAnisetteClientInfo   = nil
        ud.customAnisetteUserAgent    = nil
        ud.customAnisetteDeviceID     = nil
        ud.customAnisetteLocalUserID  = nil
        ud.customAnisetteLocale       = nil
        ud.customAnisetteTimeZone     = nil
        ud.customAnisetteXcodeVersion = nil
        ud.customAnisetteSerialNumber = nil
        ud.customAnisetteRoutingInfo  = nil
        deleteConfigFile()

        let serverHeaders = loadServerHeaders()
        let serverClientInfo = serverHeaders["client_info"] ?? serverHeaders["clientInfo"] ?? serverHeaders["X-MMe-Client-Info"] ?? serverHeaders["X-Mme-Client-Info"]
        let serverUserAgent = serverHeaders["user_agent"] ?? serverHeaders["userAgent"] ?? serverHeaders["User-Agent"]

        let fallbackCI = Self.normalizedClientInfo(serverClientInfo)
        let resolvedCI = fallbackCI.isEmpty ? AppConstants.Anisette.defaultClientInfo : fallbackCI
        let fallbackUA = serverUserAgent?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resolvedUA = fallbackUA.isEmpty ? AppConstants.Anisette.defaultUserAgent : fallbackUA

        let config = AnisetteConfig(
            clientInfo: resolvedCI,
            userAgent: resolvedUA
        )
        return config
    }
    
    public nonisolated func deleteConfigFile() {
        try? FileManager.default.removeItem(at: configFileURL)
    }
    
    public nonisolated func hasConfigFile() -> Bool {
        return FileManager.default.fileExists(atPath: configFileURL.path)
    }
}
