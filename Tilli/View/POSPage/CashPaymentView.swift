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

    @Binding var event: EventModel

    @Environment(\.closeCheckoutFlow) private var closeFlow

    @ObservedObject var viewModel: CashPaymentViewModel

    @AppStorage("calculatorEnabled") private var calculatorEnabled = true

    enum FocusField: Hashable {
        case receivedAmount
    }

    @FocusState private var focusedField: FocusField?

    init(
        totalAmount: Decimal,
        event: Binding<EventModel>,
        summaryItems: [SummaryItemModel],
        selectedDiscount: DiscountModel? = nil,
        occurredAt: Date? = nil
    ) {
        self._event = event
        self._viewModel = ObservedObject(wrappedValue: CashPaymentViewModel(
            totalAmount: totalAmount,
            event: event.wrappedValue,
            summaryItems: summaryItems,
            selectedDiscount: selectedDiscount,
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

    // MARK: - 完整計算機模式
    private var calculatorModeView: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
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

                TextField(viewModel.currencyPlaceholder, text: $viewModel.receivedAmountText)
                    .keyboardType(viewModel.supportsDecimal ? .decimalPad : .numberPad)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                            .stroke(DesignSystem.ColorToken.muted.opacity(0.3))
                    )
                    .focused($focusedField, equals: .receivedAmount)
                    .submitLabel(.done)
                    .onChange(of: viewModel.receivedAmountText) {
                        let validatedAmount = viewModel.validateAndFormatAmount(viewModel.receivedAmountText)
                        if validatedAmount != viewModel.receivedAmountText {
                            viewModel.receivedAmountText = validatedAmount
                        }
                    }
                    .onSubmit {
                        completePayment()
                    }
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

            Spacer()

            VStack(spacing: DesignSystem.Spacing.sm) {
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
        }
        .padding()
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.focusedField = .receivedAmount
            }
        }
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

        let updateEvent = viewModel.performCheckout(
            eventDataManager: eventDataManager,
            productRepository: productRepository,
            inventoryChangeRepository: inventoryChangeRepository
        )
        event = updateEvent

        focusedField = nil

          DispatchQueue.main.async {
            closeFlow()
        }
    }

    private func completePaymentSimple() {
        let updateEvent = viewModel.performCheckout(
            eventDataManager: eventDataManager,
            productRepository: productRepository,
            inventoryChangeRepository: inventoryChangeRepository
        )
        event = updateEvent
        closeFlow()
    }
}
