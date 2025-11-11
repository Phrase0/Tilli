//
//  SessionsViewModel.swift
//  Tilli
//
//  Created by Peiyun on 2025/4/23.
//

import Foundation

class SessionViewModel: ObservableObject {
    
    // 複製場次相關狀態
    @Published var showDuplicateSessionDialog = false
    @Published var sessionToDuplicate: SessionModel? = nil
    @Published var duplicateSessionName = ""
    @Published var duplicateSessionDate = Date()
    @Published var hasEditedSessionName = false

    func sortedFilteredSessions(by keyword: String, from sessions: [SessionModel]) -> [SessionModel] {
        let filtered = filteredSessions(by: keyword, from: sessions)

        return filtered.sorted {
            switch ($0.status, $1.status) {
            case (.ongoing, _): return true
            case (_, .ongoing): return false
            case (.upcoming, .completed): return true
            case (.completed, .upcoming): return false
            default:
                return $0.startDate > $1.startDate // 同類型比日期
            }
        }
    }

    func filteredSessions(by keyword: String, from sessions: [SessionModel]) -> [SessionModel] {
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
    }

    func updateSession(_ updatedSession: SessionModel, using sessionDataManager: SessionDataManager) {
        sessionDataManager.updateSession(updatedSession)
    }
    
    func deleteSession(_ session: SessionModel, using sessionDataManager: SessionDataManager) {
        sessionDataManager.deleteSession(session.id)
    }
    
    func duplicateSession(_ originalSession: SessionModel, newTitle: String, newDate: Date, using sessionDataManager: SessionDataManager) -> SessionModel? {
        let duplicatedSession = sessionDataManager.duplicateSession(originalSessionId: originalSession.id, newTitle: newTitle, newDate: newDate)
        return duplicatedSession
    }
    
    // MARK: - 複製場次 UI 邏輯
    
    /// 計算確定按鈕是否應該被禁用
    var isDuplicateButtonDisabled: Bool {
        // 如果沒有編輯過，一律可以按
        if !hasEditedSessionName {
            return false
        }
        // 如果有編輯過，檢查文字是否為空
        return duplicateSessionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    /// 開始複製場次操作
    func startDuplicateSession(_ session: SessionModel) {
        sessionToDuplicate = session
        duplicateSessionName = session.title
        duplicateSessionDate = session.startDate
        hasEditedSessionName = false
        showDuplicateSessionDialog = true
    }
    
    /// 場次名稱編輯時調用
    func onSessionNameChanged() {
        hasEditedSessionName = true
    }
    
    /// 確認複製場次
    func confirmDuplicateSession(using sessionDataManager: SessionDataManager) {
        guard let sessionToDuplicate = sessionToDuplicate,
              !duplicateSessionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        
        let _ = duplicateSession(
            sessionToDuplicate,
            newTitle: duplicateSessionName.trimmingCharacters(in: .whitespacesAndNewlines),
            newDate: duplicateSessionDate,
            using: sessionDataManager
        )
        
        closeDuplicateDialog()
    }
    
    /// 取消複製場次
    func cancelDuplicateSession() {
        closeDuplicateDialog()
    }
    
    /// 關閉複製對話框並重置狀態
    private func closeDuplicateDialog() {
        showDuplicateSessionDialog = false
        sessionToDuplicate = nil
        duplicateSessionName = ""
        hasEditedSessionName = false
    }
}

