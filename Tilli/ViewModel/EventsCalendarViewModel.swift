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
        eventDataManager: EventRepository
    ) {
        calendarVM.updateDataManagers(
            transactionDataManager: transactionDataManager,
            eventDataManager: eventDataManager
        )
    }

    // MARK: - Calendar Delegation

    func changeMonth(_ direction: Int) {
        calendarVM.changeMonth(direction, currentDate: &currentDate)
    }

    func daysInMonth() -> [Date] {
        calendarVM.daysInMonth(for: currentDate)
    }

    func eventsForDate(_ date: Date, from events: [EventModel]) -> [EventModel] {
        calendarVM.eventsForDate(date, from: events)
    }

    func hasTransactions(on date: Date) -> Bool {
        calendarVM.hasTransactions(on: date)
    }

    func getAllEventsForDate(from events: [EventModel]) -> (real: [EventModel], virtual: [EventModel]) {
        calendarVM.getAllEventsForDate(selectedDate, from: events)
    }

    func getPermanentEvents(from events: [EventModel]) -> [EventModel] {
        calendarVM.getPermanentEvents(from: events, selectedDate: selectedDate)
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

    func transactionSummary(for event: EventModel) -> (count: Int, total: Decimal) {
        let result = calendarVM.calculateTransactionSummary(for: event)
        return (result.count, result.totalAmount)
    }
}
