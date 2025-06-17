//
//  SessionsViewModel.swift
//  Tilli
//
//  Created by Peiyun on 2025/4/23.
//

import Foundation
import Combine

class SessionViewModel: ObservableObject {
    @Published var sessions: [SessionModel] = [
        SessionModel(
            id: UUID(),
            title: "Session A",
            date: Date(),
            status: .ongoing,
            amount: 5200,
            categories: ["Breakfast", "Lunch"]
        ),
        SessionModel(
            id: UUID(),
            title: "Session B",
            date: Date().addingTimeInterval(86400),
            status: .completed,
            amount: 8300,
            categories: ["Dinner"]
        )
    ]
    
    func addSession(title: String, date: Date, status: SessionStatus, amount: Int, categories: [String] = []) {
        let newSession = SessionModel(
            id: UUID(),
            title: title,
            date: date,
            status: status,
            amount: amount,
            categories: categories
        )
        sessions.append(newSession)
    }

    func removeSession(id: UUID) {
        sessions.removeAll { $0.id == id }
    }

    func filtered(by keyword: String) -> [SessionModel] {
        if keyword.isEmpty { return sessions }
        return sessions.filter {
            $0.title.localizedStandardContains(keyword) ||
            keyword.localizedStandardContains($0.title) // 支援模糊、拼音比對
        }
    }
}

