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

    @Binding var event: EventModel

    @Environment(\.dismiss) private var dismiss

    @StateObject private var viewModel = CheckoutSummaryViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // MARK: 商品清單
            ScrollView {
                VStack(spacing: DesignSystem.Spacing.md) {
                    ForEach(selectedItems) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxs) {
                                Text(item.name)
                                    .font(DesignSystem.Typography.body)

                                HStack(spacing: DesignSystem.Spacing.xs) {
                                    // 數量: %d
                                    Text("checkoutItemQuantity \(item.quantity)")
                                        .font(DesignSystem.Typography.caption)
                                        .foregroundColor(DesignSystem.ColorToken.muted)

                                    Text(item.price.money(currency: event.currency))
                                        .font(DesignSystem.Typography.caption)
                                        .foregroundColor(DesignSystem.ColorToken.muted)
                                }
                            }

                            Spacer()

                            Text(item.total.money(currency: event.currency))
                                .font(DesignSystem.Typography.body)
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
                        viewModel.toggleBackdatedMode(for: event)
                    }
                } label: {
                    HStack(spacing: DesignSystem.Spacing.xxs) {
                        Image(systemName: viewModel.isBackdatedMode ? "clock.badge.checkmark.fill" : "clock.arrow.circlepath")
                            .foregroundColor(viewModel.isBackdatedMode ? DesignSystem.ColorToken.alertRed : DesignSystem.ColorToken.muted)
                        // 補記帳
                        Text("checkoutBackdated")
                            .font(DesignSystem.Typography.body)
                            .foregroundColor(viewModel.isBackdatedMode ? DesignSystem.ColorToken.alertRed : DesignSystem.ColorToken.muted)
                    }
                    .padding(.horizontal, DesignSystem.Spacing.sm)
                    .padding(.vertical, DesignSystem.Spacing.xxs)
                    .background(viewModel.isBackdatedMode ? DesignSystem.ColorToken.alertRed.opacity(0.1) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.sm))
                }
                .buttonStyle(PlainButtonStyle())

                Spacer()

                if viewModel.isBackdatedMode, let range = viewModel.backdatedDateRange {
                    DatePicker(
                        "",
                        selection: $viewModel.backdatedDate,
                        in: range,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .labelsHidden()
                    .datePickerStyle(.compact)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, DesignSystem.Spacing.xs)

            // MARK: 總金額
            HStack {
                // 總計
                Text("checkoutTotalLabel")
                    .font(DesignSystem.Typography.body)
                    .fontWeight(.semibold)
                Spacer()

                if let discount = selectedDiscount {
                    Text(discount.displayText(currency: event.currency))
                        .font(DesignSystem.Typography.caption)
                        .padding(.horizontal, DesignSystem.Spacing.xs)
                        .padding(.vertical, DesignSystem.Spacing.xxs)
                        .background(DesignSystem.ColorToken.quietFill)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                Text(totalAmount.money(currency: event.currency))
                    .font(DesignSystem.Typography.body)
                    .fontWeight(.bold)
            }
            .padding()

            // MARK: 支付方式
            VStack(spacing: DesignSystem.Spacing.xs) {
                // 現金付款
                Button {
                    viewModel.attemptCheckout(for: event, destination: .cash)
                } label: {
                    HStack {
                        Image(systemName: "banknote")
                            .foregroundColor(DesignSystem.ColorToken.ink)
                        VStack(alignment: .leading) {
                            // 現金付款
                            Text("checkoutCashTitle")
                                .foregroundColor(DesignSystem.ColorToken.ink)
                            // 使用現金付款
                            Text("checkoutCashSubtitle")
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.ColorToken.muted)
                        }
                        Spacer()
                    }
                    .padding()
                    .background(DesignSystem.ColorToken.quietFill)
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.sm))
                }

                // 電子支付
                Button {
                    viewModel.attemptCheckout(for: event, destination: .ePayment)
                } label: {
                    HStack {
                        Image(systemName: "creditcard")
                            .foregroundColor(DesignSystem.ColorToken.ink)
                        VStack(alignment: .leading) {
                            // 電子支付
                            Text("checkoutEPayTitle")
                                .foregroundColor(DesignSystem.ColorToken.ink)
                            // 使用數位錢包付款
                            Text("checkoutEPaySubtitle")
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.ColorToken.muted)
                        }
                        Spacer()
                    }
                    .padding()
                    .background(DesignSystem.ColorToken.quietFill)
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.sm))
                }
            }
            .padding()
        }
        // MARK: - Navigation Destinations
        .navigationDestination(isPresented: $viewModel.navigateToCashPayment) {
            CashPaymentView(
                totalAmount: totalAmount,
                event: $event,
                summaryItems: selectedItems,
                selectedDiscount: selectedDiscount,
                occurredAt: viewModel.occurredAtValue
            )
        }
        .navigationDestination(isPresented: $viewModel.navigateToEPayment) {
            EPaymentView(
                totalAmount: totalAmount,
                event: $event,
                summaryItems: selectedItems,
                selectedDiscount: selectedDiscount,
                occurredAt: viewModel.occurredAtValue
            )
        }
        // 無法新增交易
        .alert("checkoutDateWarningTitle", isPresented: $viewModel.showDateWarning) {
            // 確定
            Button("commonConfirm", role: .cancel) { }
        } message: {
            Text(viewModel.dateWarningMessage)
        }
        // 訂單摘要
        .navigationTitle("checkoutSummaryTitle")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .foregroundColor(DesignSystem.ColorToken.muted)
                }
            }
        }
    }
}
