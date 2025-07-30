//
//  AppState.swift
//  Tilli
//
//  Created by Peiyun on 2025/7/5.
//

import SwiftUI

class AppState: ObservableObject {

    @Published var currentSession: SessionModel? {
        didSet {
            SessionStorage.saveCurrentSessionId(currentSession?.id)
        }
    }
    
//    func loadCurrentSessionIfNeeded(sessionDataManager: SessionDataManager) {
//        guard let savedId = SessionStorage.loadCurrentSessionId() else {
//            currentSession = nil
//            return
//        }
//        if let session = sessionDataManager.sessions.first(where: { $0.id == savedId }) {
//            currentSession = session
//        } else {
//            currentSession = nil
//        }
//    }
}

