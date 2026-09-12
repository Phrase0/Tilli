//
//  CheckoutSummaryViewModel.swift
//  Tilli
//
//  Created by Peiyun on 2026/9/3.
//

import Foundation

class CheckoutSummaryViewModel: ObservableObject {

    enum PaymentDestination {
        case cash
        case ePayment
    }

    @Published var navigateToCashPayment = false
    @Published var navigateToEPayment = false
    @Published var showDateWarning = false
    @Published var dateWarningMessage = ""

    @Published var isBackdatedMode = false
    @Published var backdatedDate = Date()
    @Published var backdatedDateRange: ClosedRange<Date>?

    var occurredAtValue: Date? {
        isBackdatedMode ? backdatedDate : nil
    }

    private func calculateBackdatedDateRange(for event: EventModel) -> ClosedRange<Date> {
        let calendar = Calendar.current
        let startOfEventDate = calendar.startOfDay(for: event.startDate)
        let now = Date()

        let endDate: Date
        if let eventEndDate = event.endDate {
            let endOfEventEndDate = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: eventEndDate) ?? eventEndDate
            endDate = min(endOfEventEndDate, now)
        } else {
            endDate = now
        }

        return startOfEventDate...endDate
    }

    func toggleBackdatedMode(for event: EventModel) {
        isBackdatedMode.toggle()
        guard isBackdatedMode else { return }

        let range = calculateBackdatedDateRange(for: event)
        backdatedDateRange = range

        let now = Date()
        backdatedDate = range.contains(now) ? now : range.upperBound
    }

    /// 驗證交易日期是否落在場次範圍內，通過才設定導頁旗標
    func attemptCheckout(for event: EventModel, destination: PaymentDestination) {
        let dateToValidate = isBackdatedMode ? backdatedDate : Date()
        let validation = DateValidationHelper.validateTransactionDate(for: event, transactionDate: dateToValidate)

        guard validation.isValid else {
            dateWarningMessage = validation.errorMessage ?? String.localized("checkoutDateWarningDefault")
            showDateWarning = true
            return
        }

        switch destination {
        case .cash:
            navigateToCashPayment = true
        case .ePayment:
            navigateToEPayment = true
        }
    }
}
