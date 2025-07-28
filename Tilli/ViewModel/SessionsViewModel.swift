//
//  SessionsViewModel.swift
//  Tilli
//
//  Created by Peiyun on 2025/4/23.
//

import Foundation

class SessionViewModel: ObservableObject {
    @Published var sessions: [SessionModel] = []
    private let sessionDataManager: SessionDataManager
    
    init(sessionDataManager: SessionDataManager) {
        self.sessionDataManager = sessionDataManager
        loadSessions()
    }

    func loadSessions() {
        sessions = sessionDataManager.sessions
    }

    func addSession(_ session: SessionModel) {
        sessionDataManager.addSession(session)
        loadSessions()
    }

    func updateSession(_ session: SessionModel) {
        sessionDataManager.updateSession(session)
        loadSessions()
    }

    func deleteSession(_ session: SessionModel) {
        sessionDataManager.deleteSession(session)
        loadSessions()
    }

}

