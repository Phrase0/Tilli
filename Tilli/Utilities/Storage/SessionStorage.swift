//
//  SessionStorage.swift
//  Tilli
//
//  Created by Peiyun on 2025/7/29.
//
import SwiftUI

class SessionStorage {
    private static let currentSessionKey = "currentSessionID"
    
    static func saveCurrentSessionId(_ id: UUID?) {
        if let id = id {
            UserDefaults.standard.set(id.uuidString, forKey: currentSessionKey)
        } else {
            UserDefaults.standard.removeObject(forKey: currentSessionKey)
        }
    }
//
//    static func loadCurrentSessionId() -> UUID? {
//        guard let idString = UserDefaults.standard.string(forKey: currentSessionKey),
//              let uuid = UUID(uuidString: idString) else { return nil }
//        return uuid
//    }
}
