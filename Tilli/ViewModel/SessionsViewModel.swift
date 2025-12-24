//
//  SessionsViewModel.swift
//  Tilli
//
//  Created by Peiyun on 2025/4/23.
//

import Foundation

class SessionViewModel: ObservableObject {

    // MARK: - 批次選取相關狀態
    @Published var isSelectionMode = false
    @Published var selectedSessionIds: Set<UUID> = []

    // MARK: - 複製場次相關狀態
    @Published var showDuplicateSessionDialog = false
    @Published var sessionToDuplicate: SessionModel? = nil
    @Published var duplicateSessionName = ""
    @Published var duplicateSessionDate = Date()
    @Published var duplicateSessionEndDate = Date()
    @Published var duplicateSessionDateType: SessionDateType = .single
    @Published var hasEditedSessionName = false

    /// 結束日期的可選範圍（開始日期的隔天到 +30 天）
    var duplicateEndDateRange: ClosedRange<Date> {
        let calendar = Calendar.current
        let minDate = calendar.date(byAdding: .day, value: 1, to: duplicateSessionDate) ?? duplicateSessionDate
        let maxDate = calendar.date(byAdding: .day, value: 30, to: duplicateSessionDate) ?? duplicateSessionDate
        return minDate...maxDate
    }

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
    
    func duplicateSession(
        _ originalSession: SessionModel,
        newTitle: String,
        newStartDate: Date,
        newEndDate: Date?,
        newDateType: SessionDateType,
        using sessionDataManager: SessionDataManager
    ) -> SessionModel? {
        let duplicatedSession = sessionDataManager.duplicateSession(
            originalSessionId: originalSession.id,
            newTitle: newTitle,
            newStartDate: newStartDate,
            newEndDate: newEndDate,
            newDateType: newDateType
        )
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
        duplicateSessionDate = Date() // 預設為今天
        duplicateSessionDateType = session.dateType // 預設使用原場次類型
        // 設定結束日期
        if session.dateType == .multi, let endDate = session.endDate {
            let calendar = Calendar.current
            let daysDifference = calendar.dateComponents([.day], from: session.startDate, to: endDate).day ?? 1
            duplicateSessionEndDate = calendar.date(byAdding: .day, value: daysDifference, to: duplicateSessionDate) ?? duplicateSessionDate
        } else {
            duplicateSessionEndDate = Calendar.current.date(byAdding: .day, value: 1, to: duplicateSessionDate) ?? duplicateSessionDate
        }
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

        // 根據場次類型決定結束日期
        let endDate: Date? = {
            switch duplicateSessionDateType {
            case .single:
                return duplicateSessionDate // 單日：結束日期 = 開始日期
            case .multi:
                return duplicateSessionEndDate // 多日：使用選擇的結束日期
            case .permanent:
                return nil // 無限期：沒有結束日期
            }
        }()

        let _ = duplicateSession(
            sessionToDuplicate,
            newTitle: duplicateSessionName.trimmingCharacters(in: .whitespacesAndNewlines),
            newStartDate: duplicateSessionDate,
            newEndDate: endDate,
            newDateType: duplicateSessionDateType,
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
        duplicateSessionDateType = .single
        duplicateSessionEndDate = Date()
        hasEditedSessionName = false
    }

    // MARK: - 批次選取 UI 邏輯

    /// 進入選取模式
    func enterSelectionMode() {
        isSelectionMode = true
        selectedSessionIds.removeAll()
    }

    /// 退出選取模式
    func exitSelectionMode() {
        isSelectionMode = false
        selectedSessionIds.removeAll()
    }

    /// 切換單一場次的選取狀態
    func toggleSelection(sessionId: UUID) {
        if selectedSessionIds.contains(sessionId) {
            selectedSessionIds.remove(sessionId)
        } else {
            selectedSessionIds.insert(sessionId)
        }
    }

    /// 全選（傳入當前顯示的場次列表）
    func selectAll(sessions: [SessionModel]) {
        selectedSessionIds = Set(sessions.map { $0.id })
    }

    /// 取消全選
    func deselectAll() {
        selectedSessionIds.removeAll()
    }

    /// 檢查是否已全選（根據當前顯示的場次列表）
    func isAllSelected(sessions: [SessionModel]) -> Bool {
        guard !sessions.isEmpty else { return false }
        return sessions.allSatisfy { selectedSessionIds.contains($0.id) }
    }

    /// 已選取的數量
    var selectedCount: Int {
        selectedSessionIds.count
    }

    /// 刪除按鈕是否禁用
    var isDeleteButtonDisabled: Bool {
        selectedSessionIds.isEmpty
    }

    /// 批次刪除選取的場次
    func deleteSelectedSessions(using sessionDataManager: SessionDataManager) {
        for sessionId in selectedSessionIds {
            sessionDataManager.deleteSession(sessionId)
        }
        exitSelectionMode()
    }
}

