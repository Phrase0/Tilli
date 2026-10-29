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
                            name: row.bundle.name,
                            quantity: row.quantity,
                            unitPrice: row.bundle.price,
                            lineTotal: row.lineTotal,
                            isInCombo: false
                        )
                    }
                    ForEach(pricing.productRows, id: \.product.id) { row in
                        itemRow(
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

            // MARK: 組合折抵（可取消，只對這一筆有效，§5.4）
            if !pricing.combos.isEmpty || !posViewModel.cancelledCombos.isEmpty {
                VStack(spacing: DesignSystem.Spacing.xs) {
                    ForEach(pricing.combos, id: \.bundleId) { combo in
                        comboRow(combo)
                    }
                    ForEach(posViewModel.cancelledCombos) { bundle in
                        cancelledComboRow(bundle)
                    }
                }
                .padding(.horizontal)
                .padding(.top, DesignSystem.Spacing.xs)
            }

            // MARK: 總金額
            HStack {
                // 總計
                Text("checkoutTotalLabel")
                    .font(DesignSystem.Typography.body)
                    .fontWeight(.semibold)
                Spacer()

                ForEach(pricing.discounts) { discount in
                    // 減額顯示成 -77 而不是 NT$77 —— 這裡表達的是「扣掉多少」，
                    // 幣別由右邊的總計金額表達（與 POS 的 chip 一致）
                    Text(DiscountCalculator.deductionText(
                        type: discount.type,
                        value: discount.value
                    ))
                    .font(DesignSystem.Typography.caption)
                    .padding(.horizontal, DesignSystem.Spacing.xs)
                    .padding(.vertical, DesignSystem.Spacing.xxs)
                    .background(DesignSystem.ColorToken.quietFill)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                Text(pricing.total.money(currency: event.currency))
                    .font(DesignSystem.Typography.body)
                    .fontWeight(.bold)
            }
            .padding()

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

    private func itemRow(name: String, quantity: Int, unitPrice: Decimal, lineTotal: Decimal, isInCombo: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxs) {
                HStack(spacing: DesignSystem.Spacing.xs) {
                    Text(name)
                        .font(DesignSystem.Typography.body)

                    if isInCombo {
                        // 含組合
                        TagLabel("checkoutInComboTag")
                    }
                }

                HStack(spacing: DesignSystem.Spacing.xs) {
                    // 數量: %d
                    Text("checkoutItemQuantity \(quantity)")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.ColorToken.muted)

                    Text(unitPrice.money(currency: event.currency))
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.ColorToken.muted)
                }
            }

            Spacer()

            Text(lineTotal.money(currency: event.currency))
                .font(DesignSystem.Typography.body)
                .fontWeight(.semibold)
        }
    }

    /// 「名稱 × N 組　−金額」＋「取消」
    private func comboRow(_ combo: ComboApplication) -> some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            // %@ × %lld 組
            Text("checkoutComboLine \(combo.name) \(combo.groupCount)")
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.ColorToken.ink)

            Spacer()

            Text(DiscountCalculator.deductionText(type: .amount, value: combo.deduction))
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.ColorToken.ink)

            comboToggleButton(bundleId: combo.bundleId, title: "checkoutComboCancel")
        }
    }

    /// 已取消的組合：灰色劃線＋「恢復」
    private func cancelledComboRow(_ bundle: BundleModel) -> some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Text(bundle.name)
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.ColorToken.muted)
                .strikethrough()

            Spacer()

            comboToggleButton(bundleId: bundle.id, title: "checkoutComboRestore")
        }
    }

    private func comboToggleButton(bundleId: UUID, title: LocalizedStringKey) -> some View {
        Button {
            posViewModel.toggleComboCancelled(bundleId)
        } label: {
            Text(title)
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.ColorToken.ink)
                .padding(.horizontal, DesignSystem.Spacing.xs)
                .padding(.vertical, DesignSystem.Spacing.xxs)
                .background(Capsule().fill(DesignSystem.ColorToken.quietFill))
        }
        .buttonStyle(.plain)
    }
}
