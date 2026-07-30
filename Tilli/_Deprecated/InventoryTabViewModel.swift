//
//  InventoryTabViewModel.swift
//  Tilli
//
//  Created by Peiyun on 2025/1/12.
//

import Foundation

class InventoryTabViewModel: ObservableObject {

    /// 篩選並排序場次列表（排序邏輯與 SessionsView 一致）
    func sortedFilteredEvents(by keyword: String, from sessions: [EventModel]) -> [EventModel] {
        let filtered = filteredEvents(by: keyword, from: sessions)

        // 排序：進行中 > 即將開始 > 已結束，同類型按日期降序
        return filtered.sorted {
            switch ($0.status, $1.status) {
            case (.ongoing, _): return true
            case (_, .ongoing): return false
            case (.upcoming, .completed): return true
            case (.completed, .upcoming): return false
            default:
                return $0.startDate > $1.startDate
            }
        }
    }

    private func filteredEvents(by keyword: String, from sessions: [EventModel]) -> [EventModel] {
        if keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return sessions
        } else {
            return sessions.filter {
                $0.title.localizedCaseInsensitiveContains(keyword)
            }
        }
    }
}
