//
//  AppState.swift
//  Tilli
//
//  Created by Peiyun on 2025/7/5.
//

import SwiftUI

class AppState: ObservableObject {
    
    @Published var sessions: [SessionModel] = [] {
        didSet {
            // 若目前的 currentSession 被刪除，就清空
            if let current = currentSession, !sessions.contains(where: { $0.id == current.id }) {
                currentSession = nil
            }
        }
    }

    @Published var currentSession: SessionModel? {
        didSet {
            SessionStorage.saveCurrentSessionId(currentSession?.id)
        }
    }

//    func restoreCurrentSessionIfNeeded() {
//        if let savedId = SessionStorage.loadCurrentSessionId(),
//           let session = sessions.first(where: { $0.id == savedId }) {
//            currentSession = session
//        }
//    }

//    @Published var currentSummaryItems: [SummaryItemModel] = []
//    @Published var transactionRecords: [[SummaryItemModel]] = []
}

