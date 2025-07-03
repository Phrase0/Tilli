//
//  Untitled.swift
//  Tilli
//
//  Created by Peiyun on 2025/7/3.
//

import SwiftUI
// 全局共享物件
class SessionStore: ObservableObject {
    @Published var sessions: [SessionModel] = []

    init() {
        // 預設加入一筆 session
        let defaultSession = SessionModel(
            title: "預設場次",
            date: Date(),
            status: .ongoing,
            amount: 0,
            categories: ["食物", "交通", "住宿"],
            createdAt: Date(),
            products: []
        )
        sessions.append(defaultSession)
    }
}
