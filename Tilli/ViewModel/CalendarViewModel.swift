//
//  CalendarViewModel.swift
//  Tilli
//
//  Created by Peiyun on 2025/9/8.
//

import SwiftUI

class CalendarViewModel: ObservableObject {
    
    @Published var transactionViewModel: TransactionViewModel
    // 注意：移除本地 sessions 陣列，直接使用 SessionDataManager 的 @Published sessions
    
    @Binding var selectedSession: SessionModel
    
    private var sessionDataManager: SessionDataManager?
    private var transactionDataManager: TransactionDataManager?
    
    init(session: Binding<SessionModel>) {
        self._selectedSession = session
        self.transactionViewModel = TransactionViewModel(session: session)
    }
    
    // MARK: - DataManager 管理
    
    /// 更新 DataManager 引用給所有子 ViewModel
    func updateDataManagers(
        transactionDataManager: TransactionDataManager,
        sessionDataManager: SessionDataManager
    ) {
        self.sessionDataManager = sessionDataManager
        self.transactionDataManager = transactionDataManager
        
        transactionViewModel.updateDataManagers(
            transactionDataManager: transactionDataManager
        )
    }
    
    /// 刷新數據（已不需要手動刷新，SessionDataManager 會自動更新）
    func refresh(using sessionDataManager: SessionDataManager) {
        self.sessionDataManager = sessionDataManager
    }
    
    // MARK: - Calendar Functions
    
    private let calendar = Calendar.current
    
    /// 計算當月的所有日期
    func daysInMonth(for currentDate: Date) -> [Date] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: currentDate) else {
            return []
        }
        
        let firstOfMonth = monthInterval.start
        let firstWeekday = calendar.component(.weekday, from: firstOfMonth)
        
        // 調整為星期日開始 (weekday: 1=Sunday, 2=Monday, ...)
        let adjustedFirstWeekday = firstWeekday - 1
        let startDate = calendar.date(byAdding: .day, value: -(adjustedFirstWeekday), to: firstOfMonth)!
        
        // 計算這個月有多少天
        let range = calendar.range(of: .day, in: .month, for: currentDate)!
        let daysInCurrentMonth = range.count
        
        // 計算需要的總格數
        let totalCellsNeeded = adjustedFirstWeekday + daysInCurrentMonth
        
        // 決定需要多少週 (最少5週，最多6週)
        let weeksNeeded = totalCellsNeeded <= 35 ? 5 : 6
        let totalDays = weeksNeeded * 7
        
        var dates: [Date] = []
        var date = startDate
        
        // 生成指定週數的日期
        for _ in 0..<totalDays {
            dates.append(date)
            date = calendar.date(byAdding: .day, value: 1, to: date)!
        }
        
        return dates
    }
    
    /// 獲取指定日期的sessions
    func sessionsForDate(_ date: Date, from sessions: [SessionModel]) -> [SessionModel] {
        sessions.filter { session in
            calendar.isDate(session.date, inSameDayAs: date)
        }
    }
    
    /// 檢查指定日期是否有sessions
    func hasSessions(on date: Date, from sessions: [SessionModel]) -> Bool {
        sessions.contains { session in
            calendar.isDate(session.date, inSameDayAs: date)
        }
    }
    
    /// 檢查指定日期是否有交易記錄（包括孤兒交易）
    func hasTransactions(on date: Date) -> Bool {
        guard let transactionManager = transactionDataManager else { return false }
        let transactions = transactionManager.fetchTransactions(for: date)
        return !transactions.isEmpty
    }
    
    /// 獲取指定日期的所有交易記錄分組（按SessionId）
    func transactionGroupsForDate(_ date: Date) -> [String: [TransactionModel]] {
        guard let transactionManager = transactionDataManager else { return [:] }
        return transactionManager.fetchTransactionsGroupedBySession(for: date)
    }
    
    /// 改變月份
    func changeMonth(_ direction: Int, currentDate: Date) -> Date? {
        return calendar.date(byAdding: .month, value: direction, to: currentDate)
    }
    
    /// 格式化月份年份字符串
    func monthYearString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_TW")
        formatter.dateFormat = "yyyy年 M月"
        return formatter.string(from: date)
    }
    
    /// 週日標題
    var weekdays: [String] {
        ["日", "一", "二", "三", "四", "五", "六"]
    }
}
