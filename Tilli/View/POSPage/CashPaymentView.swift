//
//  CashPaymentView.swift
//  Tilli
//
//  Created by Peiyun on 2025/7/22.
//

import SwiftUI
import Foundation

struct CashPaymentView: View {

    @EnvironmentObject var transactionDataManager: TransactionRepository
    @EnvironmentObject var eventDataManager: EventRepository
    @EnvironmentObject var productRepository: ProductRepository
    @EnvironmentObject var inventoryChangeRepository: InventoryChangeRepository

    let event: EventModel

    @Environment(\.closeCheckoutFlow) private var closeFlow

    @ObservedObject var viewModel: CashPaymentViewModel

    @AppStorage("calculatorEnabled") private var calculatorEnabled = true

    init(
        totalAmount: Decimal,
        event: EventModel,
        summaryItems: [SummaryItemModel],
        appliedDiscounts: [AppliedDiscount] = [],
        occurredAt: Date? = nil
    ) {
        self.event = event
        self._viewModel = ObservedObject(wrappedValue: CashPaymentViewModel(
            totalAmount: totalAmount,
            event: event,
            summaryItems: summaryItems,
            appliedDiscounts: appliedDiscounts,
            occurredAt: occurredAt
        ))
    }

    var body: some View {
        if calculatorEnabled {
            calculatorModeView
        } else {
            simpleModeView
        }
    }

    // MARK: - 完整計算機模式（自訂數字鍵盤，不使用系統鍵盤，不需要處理彈出/收起的避讓）
    private var calculatorModeView: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            VStack(spacing: DesignSystem.Spacing.xs) {
                // 總金額
                Text("checkoutAmountLabel")
                    .font(DesignSystem.Typography.body)
                    .foregroundColor(DesignSystem.ColorToken.muted)

                Text(viewModel.totalAmount.money(currency: event.currency))
                    .font(DesignSystem.Typography.display)
                    .foregroundColor(DesignSystem.ColorToken.ink)
            }

            Divider()

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                // 支付
                Text("checkoutReceivedLabel")
                    .font(DesignSystem.Typography.body)
                    .foregroundColor(DesignSystem.ColorToken.muted)

                // 純顯示用，實際輸入來自下方的自訂數字鍵盤
                Text(viewModel.receivedAmountText.isEmpty ? viewModel.currencyPlaceholder : viewModel.receivedAmountText)
                    .foregroundColor(viewModel.receivedAmountText.isEmpty
                                     ? DesignSystem.ColorToken.muted
                                     : DesignSystem.ColorToken.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                            .stroke(DesignSystem.ColorToken.muted.opacity(0.3))
                    )
            }

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                // 找零
                Text("checkoutChangeLabel")
                    .font(DesignSystem.Typography.body)
                    .foregroundColor(DesignSystem.ColorToken.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(max(viewModel.change, 0).money(currency: event.currency))
                    .font(DesignSystem.Typography.title1)
                    .foregroundColor(DesignSystem.ColorToken.ink)
                    .bold()
                    .frame(maxWidth: .infinity, alignment: .leading)

                Group {
                    if !viewModel.isAmountValid {
                        // 請輸入等於或大於總額的金額
                        Label("checkoutAmountInvalid", systemImage: "xmark.octagon.fill")
                            .foregroundColor(DesignSystem.ColorToken.alertRed)
                            .font(DesignSystem.Typography.caption)
                            .multilineTextAlignment(.leading)
                    } else {
                        Color.clear
                            .frame(height: 20)
                    }
                }
            }

            // 免找零
            Button {
                viewModel.setExactAmount()
            } label: {
                Text("checkoutExactAmountButton")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(DesignSystem.ColorToken.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DesignSystem.Spacing.sm)
                    .background(DesignSystem.ColorToken.quietFill)
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.sm))
            }

            NumericKeypad(
                showsDecimalPoint: viewModel.supportsDecimal,
                onDigit: { viewModel.appendToReceivedAmount($0) },
                onDecimalPoint: { viewModel.appendToReceivedAmount(".") },
                onDelete: { viewModel.deleteLastDigit() }
            )

            Button {
                completePayment()
            } label: {
                // 完成付款
                Text("checkoutCompleteButton")
                    .foregroundColor(DesignSystem.ColorToken.onButtonFilled)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DesignSystem.Spacing.md)
                    .background(viewModel.isAmountValid
                                ? DesignSystem.ColorToken.buttonFilled
                                : DesignSystem.ColorToken.muted)
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.md))
            }
            .disabled(!viewModel.isAmountValid)
        }
        .padding()
        .navigationTitle("")
    }

    // MARK: - 簡化模式
    private var simpleModeView: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            Spacer()

            VStack(spacing: DesignSystem.Spacing.sm) {
                // 總金額
                Text("checkoutAmountLabel")
                    .font(DesignSystem.Typography.title2)
                    .foregroundColor(DesignSystem.ColorToken.muted)

                Text(viewModel.totalAmount.money(currency: event.currency))
                    .font(.system(size: 48, weight: .bold))
                    .foregroundColor(DesignSystem.ColorToken.ink)
            }

            Spacer()
            Spacer()

            Button {
                completePaymentSimple()
            } label: {
                // 完成付款
                Text("checkoutCompleteButton")
                    .foregroundColor(DesignSystem.ColorToken.onButtonFilled)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DesignSystem.Spacing.md)
                    .background(DesignSystem.ColorToken.buttonFilled)
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.md))
            }
        }
        .padding()
        .navigationTitle("")
    }

    // MARK: - Helper Methods

    private func completePayment() {
        guard viewModel.isAmountValid else { return }

        viewModel.performCheckout(
            eventDataManager: eventDataManager,
            productRepository: productRepository,
            inventoryChangeRepository: inventoryChangeRepository
        )

        DispatchQueue.main.async {
            closeFlow()
        }
    }

    private func completePaymentSimple() {
        viewModel.performCheckout(
            eventDataManager: eventDataManager,
            productRepository: productRepository,
            inventoryChangeRepository: inventoryChangeRepository
        )
        closeFlow()
    }
}

// MARK: - 自訂數字鍵盤

private struct NumericKeypad: View {
    let showsDecimalPoint: Bool
    let onDigit: (String) -> Void
    let onDecimalPoint: () -> Void
    let onDelete: () -> Void

    private let digitRows: [[String]] = [
        ["1", "2", "3"],
        ["4", "5", "6"],
        ["7", "8", "9"]
    ]

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            ForEach(digitRows, id: \.self) { row in
                HStack(spacing: DesignSystem.Spacing.sm) {
                    ForEach(row, id: \.self) { digit in
                        keyButton(label: digit) { onDigit(digit) }
                    }
                }
            }

            HStack(spacing: DesignSystem.Spacing.sm) {
                if showsDecimalPoint {
                    keyButton(label: ".") { onDecimalPoint() }
                } else {
                    Color.clear
                }
                keyButton(label: "0") { onDigit("0") }
                keyButton(systemImage: "delete.left") { onDelete() }
            }
        }
    }

    private func keyButton(label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 22, weight: .medium))
                .foregroundColor(DesignSystem.ColorToken.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(DesignSystem.ColorToken.quietFill)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.sm))
        }
    }

    private func keyButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(DesignSystem.ColorToken.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(DesignSystem.ColorToken.quietFill)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.sm))
        }
    }
}
