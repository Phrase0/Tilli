//
//  EventsCalendarViewModel.swift
//  Tilli
//
//  Created by Peiyun on 2026/7/29.
//

import SwiftUI

class EventsCalendarViewModel: ObservableObject {

    @Published var currentDate = Date()
    @Published var selectedDate = Date()
    @Published var showingMonthYearPicker = false

    private var transactionDataManager: TransactionRepository?

    private let calendar = Calendar.current

    // MARK: - DataManager

    func updateDataManagers(transactionDataManager: TransactionRepository) {
        self.transactionDataManager = transactionDataManager
    }

    // MARK: - Calendar

    func changeMonth(_ direction: Int) {
        if let newDate = calendar.date(byAdding: .month, value: direction, to: currentDate) {
            currentDate = newDate
        }
    }

    /// 計算當月的所有日期
    func daysInMonth() -> [Date] {
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

    /// 獲取所有永久場次（固定顯示在日曆下方）
    /// 只返回 startDate <= 當前選中日期的永久場次
    func getPermanentEvents(from events: [EventModel]) -> [EventModel] {
        let selectedDay = calendar.startOfDay(for: selectedDate)
        return events.filter { event in
            guard event.dateType == .permanent else { return false }
            let startDay = calendar.startOfDay(for: event.startDate)
            return startDay <= selectedDay  // 只顯示已經開始的永久場次
        }
    }

    var weekdays: [String] {
        calendar.veryShortWeekdaySymbols
    }

    func monthYearString() -> String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("yMMMM")
        return formatter.string(from: currentDate)
    }

    func selectedDateString() -> String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMdEEE")
        return formatter.string(from: selectedDate)
    }

    /// 取得選中日期的所有場次（排除永久場次）
    /// 永久場次會固定顯示在日曆下方，不需要在這裡返回
    func getAllEventsForDate(from events: [EventModel]) -> [EventModel] {
        let allEvents = eventsForDate(selectedDate, from: events)
        return allEvents.filter { $0.dateType != .permanent }
    }

    // MARK: - Transaction Calculations

    /// 計算 Event 的交易摘要（筆數 + 總金額）
    func transactionSummary(for event: EventModel) -> (count: Int, total: Decimal) {
        guard let transactionManager = transactionDataManager else {
            return (count: 0, total: 0)
        }
        let transactions = transactionManager.fetchTransactions(forEventId: event.id)
        let total = transactions.reduce(Decimal(0)) { MoneyHelper.add($0, $1.totalAmount) }
        return (count: transactions.count, total: total)
    }
}
