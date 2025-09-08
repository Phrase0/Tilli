//
//  CalendarViewModel.swift
//  Tilli
//
//  Created by Peiyun on 2025/9/8.
//

import SwiftUI

class CalendarViewModel: ObservableObject {
    
    @Published var transactionViewModel: TransactionViewModel
    @Published var sessions: [SessionModel] = []
    
    @Binding var selectedSession: SessionModel
    
    private var sessionDataManager: SessionDataManager?
    
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
        
        transactionViewModel.updateDataManagers(
            transactionDataManager: transactionDataManager
        )
    }
    
    /// 刷新數據
    func refresh(using sessionDataManager: SessionDataManager) {
        self.sessionDataManager = sessionDataManager
        sessions = sessionDataManager.sessions
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
        
        // 調整為星期一開始 (weekday: 1=Sunday, 2=Monday, ...)
        let adjustedFirstWeekday = firstWeekday == 1 ? 6 : firstWeekday - 2
        let startDate = calendar.date(byAdding: .day, value: -(adjustedFirstWeekday), to: firstOfMonth)!
        
        var dates: [Date] = []
        var date = startDate
        
        // 生成6週的日期
        for _ in 0..<42 {
            dates.append(date)
            date = calendar.date(byAdding: .day, value: 1, to: date)!
        }
        
        return dates
    }
    
    /// 獲取指定日期的sessions
    func sessionsForDate(_ date: Date) -> [SessionModel] {
        sessions.filter { session in
            calendar.isDate(session.date, inSameDayAs: date)
        }
    }
    
    /// 檢查指定日期是否有sessions
    func hasSessions(on date: Date) -> Bool {
        sessions.contains { session in
            calendar.isDate(session.date, inSameDayAs: date)
        }
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
        ["一", "二", "三", "四", "五", "六", "日"]
    }
}
