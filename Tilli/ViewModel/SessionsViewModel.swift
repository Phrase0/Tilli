//
//  SessionsViewModel.swift
//  Tilli
//
//  Created by Peiyun on 2025/4/23.
//

import Foundation

class SessionViewModel: ObservableObject {
    @Published var sessions: [SessionModel] = []

    func sortedFilteredSessions(by keyword: String) -> [SessionModel] {
        let filtered = filteredSessions(by: keyword)

        return filtered.sorted {
            switch ($0.status, $1.status) {
            case (.ongoing, _): return true
            case (_, .ongoing): return false
            case (.upcoming, .completed): return true
            case (.completed, .upcoming): return false
            default:
                return $0.date > $1.date // 同類型比日期
            }
        }
    }

    func filteredSessions(by keyword: String) -> [SessionModel] {
        if keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return sessions
        } else {
            return sessions.filter {
                $0.title.localizedCaseInsensitiveContains(keyword)
            }
        }
    }

    
    func addSession(_ newSession: SessionModel, using sessionDataManager: SessionDataManager) {
        sessionDataManager.addSession(newSession)
        sessions = sessionDataManager.sessions
    }

    func updateSession(_ updatedSession: SessionModel, using sessionDataManager: SessionDataManager) {
        sessionDataManager.updateSession(updatedSession)
        sessions = sessionDataManager.sessions
    }
    
    func deleteSession(_ session: SessionModel,using sessionDataManager: SessionDataManager) {
        sessionDataManager.deleteSession(session)
        sessions = sessionDataManager.sessions
    }
    
    func refresh(using sessionDataManager: SessionDataManager) {
        sessions = sessionDataManager.sessions
    }
}

