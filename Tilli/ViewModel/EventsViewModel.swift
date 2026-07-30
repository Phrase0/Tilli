//
//  EventsViewModel.swift
//  Tilli
//
//  Created by Peiyun on 2025/4/23.
//

import SwiftUI

class EventsViewModel: ObservableObject {
    @Published var displayMode: EventsDisplayMode = .list

    // MARK: - 批次選取相關狀態
    @Published var isSelectionMode = false
    @Published var selectedEventIds: Set<UUID> = []

    // MARK: - 複製場次相關狀態
    @Published var showDuplicateEventDialog = false
    @Published var eventToDuplicate: EventModel? = nil
    @Published var duplicateEventName = ""
    @Published var duplicateEventDate = Date()
    @Published var duplicateEventEndDate = Date()
    @Published var duplicateEventDateType: EventDateType = .single
    @Published var hasEditedEventName = false

    private var transactionDataManager: TransactionRepository?

    func updateDataManagers(transactionDataManager: TransactionRepository) {
        self.transactionDataManager = transactionDataManager
    }

    func transactionSummary(for event: EventModel) -> (count: Int, total: Decimal) {
        guard let manager = transactionDataManager else { return (0, 0) }
        let transactions = manager.fetchTransactions(forEventId: event.id)
        let total = transactions.reduce(Decimal.zero) { $0 + $1.totalAmount }
        return (transactions.count, total)
    }

    /// 結束日期的可選範圍（開始日期的隔天到 +30 天）
    var duplicateEndDateRange: ClosedRange<Date> {
        let calendar = Calendar.current
        let minDate = calendar.date(byAdding: .day, value: 1, to: duplicateEventDate) ?? duplicateEventDate
        let maxDate = calendar.date(byAdding: .day, value: 30, to: duplicateEventDate) ?? duplicateEventDate
        return minDate...maxDate
    }

    func sortedFilteredEvents(by keyword: String, from events: [EventModel]) -> [EventModel] {
        let filtered = filteredEvents(by: keyword, from: events)

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

    func filteredEvents(by keyword: String, from events: [EventModel]) -> [EventModel] {
        if keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return events
        } else {
            return events.filter {
                $0.title.localizedCaseInsensitiveContains(keyword)
            }
        }
    }

    func addEvent(_ newEvent: EventModel, using eventDataManager: EventRepository) {
        eventDataManager.addEvent(newEvent)
    }

    func updateEvent(_ updatedEvent: EventModel, using eventDataManager: EventRepository) {
        eventDataManager.updateEvent(updatedEvent)
    }

    func deleteEvent(_ event: EventModel, using eventDataManager: EventRepository) {
        eventDataManager.deleteEvent(event.id)
    }

    func duplicateEvent(
        _ originalEvent: EventModel,
        newTitle: String,
        newStartDate: Date,
        newEndDate: Date?,
        newDateType: EventDateType,
        using eventDataManager: EventRepository
    ) -> EventModel? {
        let duplicatedEvent = eventDataManager.duplicateEvent(
            originalEventId: originalEvent.id,
            newTitle: newTitle,
            newStartDate: newStartDate,
            newEndDate: newEndDate,
            newDateType: newDateType
        )
        return duplicatedEvent
    }

    // MARK: - 複製場次 UI 邏輯

    var isDuplicateButtonDisabled: Bool {
        if !hasEditedEventName {
            return false
        }
        return duplicateEventName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func startDuplicateEvent(_ event: EventModel) {
        eventToDuplicate = event
        duplicateEventName = event.title
        duplicateEventDate = Date()
        duplicateEventDateType = event.dateType
        if event.dateType == .multi, let endDate = event.endDate {
            let calendar = Calendar.current
            let daysDifference = calendar.dateComponents([.day], from: event.startDate, to: endDate).day ?? 1
            duplicateEventEndDate = calendar.date(byAdding: .day, value: daysDifference, to: duplicateEventDate) ?? duplicateEventDate
        } else {
            duplicateEventEndDate = Calendar.current.date(byAdding: .day, value: 1, to: duplicateEventDate) ?? duplicateEventDate
        }
        hasEditedEventName = false
        showDuplicateEventDialog = true
    }

    func onEventNameChanged() {
        hasEditedEventName = true
    }

    func confirmDuplicateEvent(using eventDataManager: EventRepository) {
        guard let eventToDuplicate = eventToDuplicate,
              !duplicateEventName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        let endDate: Date? = {
            switch duplicateEventDateType {
            case .single:
                return duplicateEventDate
            case .multi:
                return duplicateEventEndDate
            case .permanent:
                return nil
            }
        }()

        let _ = duplicateEvent(
            eventToDuplicate,
            newTitle: duplicateEventName.trimmingCharacters(in: .whitespacesAndNewlines),
            newStartDate: duplicateEventDate,
            newEndDate: endDate,
            newDateType: duplicateEventDateType,
            using: eventDataManager
        )

        closeDuplicateDialog()
    }

    func cancelDuplicateEvent() {
        closeDuplicateDialog()
    }

    private func closeDuplicateDialog() {
        showDuplicateEventDialog = false
        eventToDuplicate = nil
        duplicateEventName = ""
        duplicateEventDateType = .single
        duplicateEventEndDate = Date()
        hasEditedEventName = false
    }

    // MARK: - 批次選取 UI 邏輯

    func enterSelectionMode() {
        isSelectionMode = true
        selectedEventIds.removeAll()
    }

    func exitSelectionMode() {
        isSelectionMode = false
        selectedEventIds.removeAll()
    }

    func toggleSelection(eventId: UUID) {
        if selectedEventIds.contains(eventId) {
            selectedEventIds.remove(eventId)
        } else {
            selectedEventIds.insert(eventId)
        }
    }

    func selectAll(events: [EventModel]) {
        selectedEventIds = Set(events.map { $0.id })
    }

    func deselectAll() {
        selectedEventIds.removeAll()
    }

    func isAllSelected(events: [EventModel]) -> Bool {
        guard !events.isEmpty else { return false }
        return events.allSatisfy { selectedEventIds.contains($0.id) }
    }

    var selectedCount: Int {
        selectedEventIds.count
    }

    var isDeleteButtonDisabled: Bool {
        selectedEventIds.isEmpty
    }

    func deleteSelectedEvents(using eventDataManager: EventRepository) {
        for eventId in selectedEventIds {
            eventDataManager.deleteEvent(eventId)
        }
        exitSelectionMode()
    }
}
