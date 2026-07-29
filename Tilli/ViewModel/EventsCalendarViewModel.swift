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

    let calendarVM = CalendarViewModel()

    private let calendar = Calendar.current

    // MARK: - DataManager

    func updateDataManagers(
        transactionDataManager: TransactionRepository,
        sessionDataManager: SessionRepository
    ) {
        calendarVM.updateDataManagers(
            transactionDataManager: transactionDataManager,
            sessionDataManager: sessionDataManager
        )
    }

    // MARK: - Calendar Delegation

    func changeMonth(_ direction: Int) {
        calendarVM.changeMonth(direction, currentDate: &currentDate)
    }

    func daysInMonth() -> [Date] {
        calendarVM.daysInMonth(for: currentDate)
    }

    func sessionsForDate(_ date: Date, from sessions: [SessionModel]) -> [SessionModel] {
        calendarVM.sessionsForDate(date, from: sessions)
    }

    func hasTransactions(on date: Date) -> Bool {
        calendarVM.hasTransactions(on: date)
    }

    func getAllSessionsForDate(from sessions: [SessionModel]) -> (real: [SessionModel], virtual: [SessionModel]) {
        calendarVM.getAllSessionsForDate(selectedDate, from: sessions)
    }

    func getPermanentSessions(from sessions: [SessionModel]) -> [SessionModel] {
        calendarVM.getPermanentSessions(from: sessions, selectedDate: selectedDate)
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

    func transactionSummary(for session: SessionModel) -> (count: Int, total: Decimal) {
        let result = calendarVM.calculateTransactionSummary(for: session)
        return (result.count, result.totalAmount)
    }
}
