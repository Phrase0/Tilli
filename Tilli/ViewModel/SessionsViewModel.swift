//
//  SessionsViewModel.swift
//  Tilli
//
//  Created by Peiyun on 2025/4/23.
//

import Foundation
import Combine

class SessionViewModel: ObservableObject {
    @Published var sessions: [SessionModel] = []

    func addSession(title: String, date: Date, status: SessionStatus, amount: Int, categories: [String] = []) {
        let newSession = SessionModel(
            title: title,
            date: date,
            status: status,
//            amount: amount,
            categories: categories,
            createdAt: Date(),
            products: []
        )
        sessions.append(newSession)
    }
    
    func removeSession(id: UUID) {
        sessions.removeAll { $0.id == id }
    }

}

