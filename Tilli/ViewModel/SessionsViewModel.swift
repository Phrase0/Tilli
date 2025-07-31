//
//  SessionsViewModel.swift
//  Tilli
//
//  Created by Peiyun on 2025/4/23.
//

import Foundation

class SessionViewModel: ObservableObject {
    @Published var sessions: [SessionModel] = []

    func filteredSessions(by keyword: String) -> [SessionModel] {
        if keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return sessions
        } else {
            return sessions.filter {
                $0.title.localizedCaseInsensitiveContains(keyword)
            }
        }
    }
    
    func deleteSession(_ session: SessionModel,using sessionDataManager: SessionDataManager) {
        sessionDataManager.deleteSession(session)
        sessions = sessionDataManager.sessions
    }

}

