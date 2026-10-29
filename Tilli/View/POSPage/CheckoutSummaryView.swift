//
// CheckoutSummaryView.swift
//  Tilli
//
//  Created by Peiyun on 2025/7/13.
//

import SwiftUI
import Foundation

/// 進付款頁當下的定價快照：付款頁的 VM 只用這一份，之後購物車變動不影響已開的付款頁
private struct PaymentSnapshot {
    let items: [SummaryItemModel]
    let bundleDeductions: [RevenueAllocator.BundleDeduction]
    let discounts: [AppliedDiscount]
    let total: Decimal
}

struct CheckoutSummaryView: View {
    /// 即時讀 `pricing`；取消／恢復組合呼叫 `toggleComboCancelled`
    @ObservedObject var posViewModel: POSViewModel

    @Environment(\.dismiss) private var dismiss

    @StateObject private var viewModel = CheckoutSummaryViewModel()
    @State private var paymentSnapshot: PaymentSnapshot?

    private var event: EventModel { posViewModel.event }

    var body: some View {
        let pricing = posViewModel.pricing

        VStack(spacing: 0) {
            // MARK: 商品清單（套餐一行；順序依 pricing.bundleRows → productRows）
            ScrollView {
                VStack(spacing: DesignSystem.Spacing.md) {
                    ForEach(pricing.bundleRows, id: \.bundle.id) { row in
                        itemRow(
                            item: .bundle(row.bundle.id),
                            name: row.bundle.name,
                            quantity: row.quantity,
                            unitPrice: row.bundle.price,
                            lineTotal: row.lineTotal,
                            isInCombo: false
                        )
                    }
                    ForEach(pricing.productRows, id: \.product.id) { row in
                        itemRow(
                            item: .product(row.product.id),
                            name: row.product.name,
                            quantity: row.quantity,
                            unitPrice: row.product.price,
                            lineTotal: row.lineTotal,
                            isInCombo: row.isInCombo
                        )
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

            // MARK: 優惠明細（組合可取消／恢復，只對這一筆有效）
            DiscountBreakdownView(
                subtotal: pricing.subtotal,
                comboLines: pricing.combos.map {
                    .init(id: $0.bundleId, name: $0.name, amount: $0.deduction, isCancelled: false)
                } + posViewModel.cancelledCombos.map {
                    .init(id: $0.id, name: $0.name, amount: 0, isCancelled: true)
                },
                discounts: pricing.discounts,
                total: pricing.total,
                savings: pricing.savings,
                currency: event.currency,
                onToggleCombo: posViewModel.toggleComboCancelled
            )
            .padding(.horizontal)
            .padding(.top, DesignSystem.Spacing.xs)

            // MARK: 支付方式
            VStack(spacing: DesignSystem.Spacing.xs) {
                // 現金付款
                Button {
                    paymentSnapshot = makePaymentSnapshot()
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
                    paymentSnapshot = makePaymentSnapshot()
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
        // 訂單摘要裡把最後一項刪掉 → 沒有東西可結帳，回到收銀頁
        .onChange(of: posViewModel.isCartEmpty) { _, isEmpty in
            if isEmpty { dismiss() }
        }
        // MARK: - Navigation Destinations
        .navigationDestination(isPresented: $viewModel.navigateToCashPayment) {
            if let snapshot = paymentSnapshot {
                CashPaymentView(
                    totalAmount: snapshot.total,
                    event: event,
                    summaryItems: snapshot.items,
                    appliedDiscounts: snapshot.discounts,
                    bundleDeductions: snapshot.bundleDeductions,
                    occurredAt: viewModel.occurredAtValue
                )
            }
        }
        .navigationDestination(isPresented: $viewModel.navigateToEPayment) {
            if let snapshot = paymentSnapshot {
                EPaymentView(
                    totalAmount: snapshot.total,
                    event: event,
                    summaryItems: snapshot.items,
                    appliedDiscounts: snapshot.discounts,
                    bundleDeductions: snapshot.bundleDeductions,
                    occurredAt: viewModel.occurredAtValue
                )
            }
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

    // MARK: - 付款快照

    /// 進付款頁時才把定價拆成寫入用的列（含套餐／組合差額），交給付款 VM
    private func makePaymentSnapshot() -> PaymentSnapshot {
        let pricing = posViewModel.pricing
        let summary = pricing.summaryItems(categoryName: posViewModel.categoryName(for:), timestamp: Date())
        return PaymentSnapshot(
            items: summary.items,
            bundleDeductions: summary.bundleDeductions,
            discounts: pricing.discounts,
            total: pricing.total
        )
    }

    // MARK: - 列

    /// 一行：名稱（＋含組合）與單價；右邊增減元件（數量 1 時 − 是垃圾桶）與行小計
    private func itemRow(item: CartItemID, name: String, quantity: Int, unitPrice: Decimal, lineTotal: Decimal, isInCombo: Bool) -> some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxs) {
                HStack(spacing: DesignSystem.Spacing.xs) {
                    Text(name)
                        .font(DesignSystem.Typography.body)
                        .lineLimit(1)

                    if isInCombo {
                        // 含組合
                        TagLabel("checkoutInComboTag")
                    }
                }

                Text(unitPrice.money(currency: event.currency))
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.ColorToken.muted)
            }

            Spacer()

            QuantityStepper(
                quantity: quantity,
                isExpanded: true,
                canIncrement: posViewModel.canIncrement(item),
                trashAtOne: true,
                onIncrement: { posViewModel.increment(item, expand: false) },
                onDecrement: { posViewModel.decrement(item) },
                onExpand: {}
            )

            Text(lineTotal.money(currency: event.currency))
                .font(DesignSystem.Typography.body)
                .fontWeight(.semibold)
                .frame(minWidth: 64, alignment: .trailing)
        }
    }
}
