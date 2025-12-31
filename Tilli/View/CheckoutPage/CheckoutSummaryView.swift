//
// CheckoutSummaryView.swift
//  Tilli
//
//  Created by Peiyun on 2025/7/13.
//

import SwiftUI
import Foundation

struct CheckoutSummaryView: View {
    let selectedItems: [SummaryItemModel]
    let totalAmount: Decimal
    let selectedDiscount: DiscountModel?

    @Binding var session: SessionModel

    @Environment(\.closeCheckoutFlow) private var closeFlow

    @State private var navigateToCashPayment = false
    @State private var navigateToEPayment = false
    @State private var showDateWarning = false
    @State private var dateWarningMessage = ""

    // 補記帳狀態
    @State private var isBackdatedMode = false
    @State private var backdatedDate = Date()
    @State private var backdatedDateRange: ClosedRange<Date>?

    /// 計算補記帳日期的有效範圍（只在需要時呼叫）
    private func calculateBackdatedDateRange() -> ClosedRange<Date> {
        let calendar = Calendar.current
        let startOfSessionDate = calendar.startOfDay(for: session.startDate)
        let now = Date()

        // 結束日期
        let endDate: Date
        if let sessionEndDate = session.endDate {
            // 取 session.endDate 當天的最後一秒，再與 now 比較
            let endOfSessionEndDate = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: sessionEndDate) ?? sessionEndDate
            endDate = min(endOfSessionEndDate, now)
        } else {
            endDate = now
        }

        return startOfSessionDate...endDate
    }

    /// 補記帳時要傳遞的 occurredAt 值
    private var occurredAtValue: Date? {
        return isBackdatedMode ? backdatedDate : nil
    }

    var body: some View {
        VStack(spacing: 0) {
            // MARK: Header
            HStack {
                Text("訂單摘要")
                    .font(.headline)
                Spacer()
                Button {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    closeFlow()
                } label: {
                    Image(systemName: "xmark")
                        .foregroundColor(.gray)
                }
            }
            .padding()

            Divider()

            // MARK: 商品清單
            ScrollView {
                VStack(spacing: 16) {
                    ForEach(selectedItems) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.name)
                                    .font(.body)

                                HStack(spacing: 8) {
                                    Text("Qty: \(item.quantity)")
                                        .font(.caption)
                                        .foregroundColor(.gray)

                                    Text(item.price.money(currency: session.currency))
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                            }

                            Spacer()

                            Text(item.total.money(currency: session.currency))
                                .font(.body)
                                .fontWeight(.semibold)
                        }
                    }
                }
                .padding()
            }

            Divider()

            // MARK: 補記帳
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isBackdatedMode.toggle()
                        if isBackdatedMode {
                            // 計算日期範圍（只計算一次）
                            let range = calculateBackdatedDateRange()
                            backdatedDateRange = range

                            // 設定預設日期
                            let now = Date()
                            if range.contains(now) {
                                backdatedDate = now
                            } else {
                                // 如果當前時間不在範圍內，使用範圍的最後一個有效時間
                                backdatedDate = range.upperBound
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isBackdatedMode ? "clock.badge.checkmark.fill" : "clock.arrow.circlepath")
                            .foregroundColor(isBackdatedMode ? .orange : .gray)
                        Text("補記帳")
                            .font(.subheadline)
                            .foregroundColor(isBackdatedMode ? .orange : .gray)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(isBackdatedMode ? Color.orange.opacity(0.1) : Color.clear)
                    .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())

                Spacer()

                if isBackdatedMode, let range = backdatedDateRange {
                    DatePicker(
                        "",
                        selection: $backdatedDate,
                        in: range,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .labelsHidden()
                    .datePickerStyle(.compact)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            // MARK: 總金額
            HStack {
                Text("總計")
                    .font(.headline)
                Spacer()

                // 顯示折扣標籤
                if let discount = selectedDiscount {
                    Text(discount.displayText(currency: session.currency))
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.2))
                        .cornerRadius(4)
                }

                Text(totalAmount.money(currency: session.currency))
                    .font(.headline)
                    .bold()
            }
            .padding()

            // MARK: 支付方式
            VStack(spacing: 8) {
                // 現金付款
                Button {
                    // 先驗證日期（補記帳時用 backdatedDate，否則用當前時間）
                    let dateToValidate = isBackdatedMode ? backdatedDate : Date()
                    let validation = DateValidationHelper.validateTransactionDate(for: session, transactionDate: dateToValidate)
                    if !validation.isValid {
                        dateWarningMessage = validation.errorMessage ?? "交易日期不在場次範圍內"
                        showDateWarning = true
                        return
                    }
                    // 日期有效，導航到支付頁面
                    navigateToCashPayment = true
                } label: {
                    HStack {
                        Image(systemName: "banknote")
                        VStack(alignment: .leading) {
                            Text("現金付款")
                            Text("使用現金付款")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        Spacer()
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                }

                // 電子支付
                Button {
                    // 先驗證日期（補記帳時用 backdatedDate，否則用當前時間）
                    let dateToValidate = isBackdatedMode ? backdatedDate : Date()
                    let validation = DateValidationHelper.validateTransactionDate(for: session, transactionDate: dateToValidate)
                    if !validation.isValid {
                        dateWarningMessage = validation.errorMessage ?? "交易日期不在場次範圍內"
                        showDateWarning = true
                        return
                    }
                    // 日期有效，導航到支付頁面
                    navigateToEPayment = true
                } label: {
                    HStack {
                        Image(systemName: "creditcard")
                        VStack(alignment: .leading) {
                            Text("電子支付")
                            Text("使用數位錢包付款")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        Spacer()
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                }
            }
            .padding()
        }
        // MARK: - Navigation Destinations
        .navigationDestination(isPresented: $navigateToCashPayment) {
            CashPaymentView(
                totalAmount: totalAmount,
                session: $session,
                summaryItems: selectedItems,
                selectedDiscount: selectedDiscount,
                occurredAt: occurredAtValue
            )
        }
        .navigationDestination(isPresented: $navigateToEPayment) {
            EPaymentView(
                totalAmount: totalAmount,
                session: $session,
                summaryItems: selectedItems,
                selectedDiscount: selectedDiscount,
                occurredAt: occurredAtValue
            )
        }
        .alert("無法新增交易", isPresented: $showDateWarning) {
            Button("確定", role: .cancel) { }
        } message: {
            Text(dateWarningMessage)
        }
    }
}
