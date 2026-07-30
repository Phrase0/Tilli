//
//  CalendarViewModel.swift
//  Tilli
//
//  Created by Peiyun on 2025/9/8.
//

import SwiftUI

class CalendarViewModel: ObservableObject {

    private var eventDataManager: EventRepository?
    private var transactionDataManager: TransactionRepository?

    // MARK: - DataManager 管理

    /// 更新 DataManager 引用
    func updateDataManagers(
        transactionDataManager: TransactionRepository,
        eventDataManager: EventRepository
    ) {
        self.eventDataManager = eventDataManager
        self.transactionDataManager = transactionDataManager
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
    
    /// 獲取指定日期的events（支援多日場次）
    func eventsForDate(_ date: Date, from events: [EventModel]) -> [EventModel] {
        let day = calendar.startOfDay(for: date)

        return events.filter { event in
            let start = calendar.startOfDay(for: event.startDate)

            switch event.dateType {
            case .single:
                return day == start

            case .multi:
                guard let endDate = event.endDate else { return false }
                let end = calendar.startOfDay(for: endDate)
                return day >= start && day <= end

            case .permanent:
                return day == start  // 只在開始日期顯示圓點
            }
        }
    }

    /// 檢查指定日期是否有events
    func hasEvents(on date: Date, from events: [EventModel]) -> Bool {
        return !eventsForDate(date, from: events).isEmpty
    }

    /// 獲取所有永久場次（固定顯示在日曆下方）
    /// 只返回 startDate <= 當前選中日期的永久場次
    func getPermanentEvents(from events: [EventModel], selectedDate: Date) -> [EventModel] {
        let selectedDay = calendar.startOfDay(for: selectedDate)
        return events.filter { event in
            guard event.dateType == .permanent else { return false }
            let startDay = calendar.startOfDay(for: event.startDate)
            return startDay <= selectedDay  // 只顯示已經開始的永久場次
        }
    }
    
    /// 檢查指定日期是否有交易記錄（包括孤兒交易）
    func hasTransactions(on date: Date) -> Bool {
        guard let transactionManager = transactionDataManager else { return false }
        let transactions = transactionManager.fetchTransactions(for: date)
        return !transactions.isEmpty
    }
    
    /// 獲取指定日期的所有交易記錄分組（按EventId）
    func transactionGroupsForDate(_ date: Date) -> [String: [TransactionModel]] {
        guard let transactionManager = transactionDataManager else { return [:] }
        return transactionManager.fetchTransactionsGroupedByEvent(for: date)
    }
    
    /// 改變月份
    func changeMonth(_ direction: Int, currentDate: inout Date) {
        if let newDate = calendar.date(byAdding: .month, value: direction, to: currentDate) {
            currentDate = newDate
        }
    }
    
    /// 格式化月份年份字符串
    func monthYearString(for date: Date) -> String {
        DateFormatter.chineseYearMonth.string(from: date)
    }
    
    /// 週日標題
    var weekdays: [String] {
        ["日", "一", "二", "三", "四", "五", "六"]
    }

    // MARK: - Virtual Event Management

    /// 創建虛擬 Event（用於孤兒交易）
    func createVirtualEvent(
        eventId: UUID,
        transactions: [TransactionModel]
    ) -> EventModel {
        guard let firstTransaction = transactions.first else {
            fatalError("交易列表不能為空")
        }

        return EventModel(
            id: eventId,
            title: firstTransaction.eventTitle,  // 使用保存的原始 Event 名稱
            startDate: firstTransaction.displayDate,
            endDate: firstTransaction.displayDate,   // 虛擬 Event 為單日
            dateType: .single,
            categories: [],
            createdAt: firstTransaction.displayDate,
            currency: firstTransaction.currency    // 使用保存的幣別
        )
    }

    /// 取得指定日期的所有 Event（包括虛擬 Event，但排除永久場次）
    /// 永久場次會固定顯示在日曆下方，不需要在這裡返回
    func getAllEventsForDate(_ date: Date, from events: [EventModel]) -> (real: [EventModel], virtual: [EventModel]) {
        let allEvents = eventsForDate(date, from: events)
        // 排除永久場次（永久場次會固定顯示，不受日期選擇影響）
        let existingEvents = allEvents.filter { $0.dateType != .permanent }
        let transactionGroups = transactionGroupsForDate(date)

        var virtualEvents: [EventModel] = []

        // 找出孤兒交易並創建虛擬 Event
        for (eventIdString, transactions) in transactionGroups {
            guard let eventId = UUID(uuidString: eventIdString) else {
                continue
            }

            // 檢查是否已存在於當日場次中
            if existingEvents.contains(where: { $0.id == eventId }) {
                continue
            }

            // ⚠️ 重要：檢查該 eventId 是否對應永久場次
            // 永久場次的交易不應該作為孤兒交易顯示
            if events.contains(where: { $0.id == eventId && $0.dateType == .permanent }) {
                continue
            }

            let virtualEvent = createVirtualEvent(
                eventId: eventId,
                transactions: transactions
            )
            virtualEvents.append(virtualEvent)
        }

        return (real: existingEvents, virtual: virtualEvents)
    }

    // MARK: - Transaction Calculations

    /// 計算 Event 的交易摘要（筆數 + 總金額）
    func calculateTransactionSummary(for event: EventModel) -> (count: Int, totalAmount: Decimal) {
        guard let transactionManager = transactionDataManager else {
            return (count: 0, totalAmount: 0)
        }
        let transactions = transactionManager.fetchTransactions(forEventId: event.id)
        let total = transactions.reduce(Decimal(0)) { MoneyHelper.add($0, $1.totalAmount) }
        return (count: transactions.count, totalAmount: total)
    }
}
