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
    @Binding var isPresented: Bool
    @Binding var checkoutCompleted: Bool

    @State private var navigateToCashPayment = false
    @State private var navigateToEPayment = false
    @State private var showDateWarning = false
    @State private var dateWarningMessage = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // MARK: Header
                HStack {
                    Text("訂單摘要")
                        .font(.headline)
                    Spacer()
                    Button {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        isPresented = false
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
                        // 先驗證日期
                        let validation = DateValidationHelper.validateTransactionDate(for: session)
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
                        // 先驗證日期
                        let validation = DateValidationHelper.validateTransactionDate(for: session)
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
                    selectedDiscount: selectedDiscount
                ) { updatedSession in
                    self.session = updatedSession
                    checkoutCompleted = true
                    isPresented = false
                }
            }
            .navigationDestination(isPresented: $navigateToEPayment) {
                EPaymentView(
                    totalAmount: totalAmount,
                    session: $session,
                    summaryItems: selectedItems,
                    selectedDiscount: selectedDiscount
                ) { updatedSession in
                    self.session = updatedSession
                    checkoutCompleted = true
                    isPresented = false
                }
            }
            .alert("無法新增交易", isPresented: $showDateWarning) {
                Button("確定", role: .cancel) { }
            } message: {
                Text(dateWarningMessage)
            }
        }
    }
}
