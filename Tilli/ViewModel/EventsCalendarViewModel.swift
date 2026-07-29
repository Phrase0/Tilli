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

    func calculateTransactionSummary(for session: SessionModel) -> (count: Int, totalAmount: Decimal) {
        calendarVM.calculateTransactionSummary(for: session)
    }

    var weekdays: [String] {
        calendar.veryShortWeekdaySymbols
    }

    func monthYearString() -> String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("yMMMM")
        return formatter.string(from: currentDate)
    }

    func sessionProgressInfo(for session: SessionModel) -> String? {
        let referenceDate = calendar.startOfDay(for: selectedDate)

        switch session.dateType {
        case .single:
            return nil

        case .multi:
            guard let endDate = session.endDate else { return nil }
            let start = calendar.startOfDay(for: session.startDate)
            let end = calendar.startOfDay(for: endDate)
            let totalDays = calendar.dateComponents([.day], from: start, to: end).day! + 1

            if referenceDate >= start && referenceDate <= end {
                let currentDay = calendar.dateComponents([.day], from: start, to: referenceDate).day! + 1
                return String(localized: "calendarDayProgress \(currentDay) \(totalDays)")
            } else {
                return String(localized: "calendarTotalDays \(totalDays)")
            }

        case .permanent:
            let start = calendar.startOfDay(for: session.startDate)
            let daysSinceStart = calendar.dateComponents([.day], from: start, to: referenceDate).day! + 1
            return String(localized: "calendarDaysSinceStart \(daysSinceStart)")
        }
    }
}
