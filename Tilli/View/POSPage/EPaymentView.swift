//
//  EPaymentView.swift
//  Tilli
//
//  Created by Peiyun on 2025/7/22.
//

import SwiftUI
import Foundation

struct EPaymentView: View {

    @EnvironmentObject var transactionDataManager: TransactionRepository
    @EnvironmentObject var eventDataManager: EventRepository
    @EnvironmentObject var productRepository: ProductRepository
    @EnvironmentObject var qrCodeDataManager: QRCodeRepository
    @EnvironmentObject var inventoryChangeRepository: InventoryChangeRepository

    @Binding var event: EventModel

    @Environment(\.closeCheckoutFlow) private var closeFlow

    @ObservedObject var viewModel: EPaymentViewModel

    init(
        totalAmount: Decimal,
        event: Binding<EventModel>,
        summaryItems: [SummaryItemModel],
        selectedDiscount: DiscountModel? = nil,
        occurredAt: Date? = nil
    ) {
        self._event = event
        self._viewModel = ObservedObject(wrappedValue: EPaymentViewModel(
            totalAmount: totalAmount,
            event: event.wrappedValue,
            summaryItems: summaryItems,
            selectedDiscount: selectedDiscount,
            occurredAt: occurredAt
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: DesignSystem.Spacing.xs) {
                // 總金額
                Text("checkoutAmountLabel")
                    .font(DesignSystem.Typography.body)
                    .foregroundColor(DesignSystem.ColorToken.muted)

                Text(viewModel.totalAmount.money(currency: event.currency))
                    .font(DesignSystem.Typography.display)
                    .foregroundColor(DesignSystem.ColorToken.ink)
            }
            .padding(.top, DesignSystem.Spacing.lg)
            .padding(.bottom, DesignSystem.Spacing.md)

            Divider()

            // QR Code Section
            VStack(spacing: DesignSystem.Spacing.lg) {
                Spacer()

                ZStack {
                    RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                        .fill(DesignSystem.ColorToken.cardSurface)
                        .frame(width: 280, height: 280)
                        .shadow(
                            color: DesignSystem.Shadow.cardColor,
                            radius: DesignSystem.Shadow.cardRadius,
                            x: DesignSystem.Shadow.cardX,
                            y: DesignSystem.Shadow.cardY
                        )

                    if let qrImage = qrCodeDataManager.qrCodeImage {
                        Image(uiImage: qrImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 260, height: 260)
                            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.md))
                    } else {
                        VStack(spacing: DesignSystem.Spacing.md) {
                            Image(systemName: "qrcode")
                                .font(.system(size: 80))
                                .foregroundColor(DesignSystem.ColorToken.muted.opacity(0.3))

                            VStack(spacing: DesignSystem.Spacing.xxs) {
                                // 尚未設定收款碼
                                Text("checkoutNoQRCode")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(DesignSystem.ColorToken.muted)
                                // 請至「我的收款碼」頁面新增
                                Text("checkoutNoQRCodeHint")
                                    .font(.system(size: 14))
                                    .foregroundColor(DesignSystem.ColorToken.muted.opacity(0.7))
                            }
                        }
                    }
                }

                Spacer()
            }

            // 完成付款按鈕
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
                        .background(qrCodeDataManager.qrCodeImage != nil
                                    ? DesignSystem.ColorToken.buttonFilled
                                    : DesignSystem.ColorToken.muted)
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.md))
                }
                .disabled(qrCodeDataManager.qrCodeImage == nil)
            }
        }
        .padding()
        .background(DesignSystem.ColorToken.paper)
        .navigationTitle("")
    }

    // MARK: - Helper Methods

    private func completePayment() {
        guard qrCodeDataManager.qrCodeImage != nil else { return }

        let updateEvent = viewModel.performCheckout(
            eventDataManager: eventDataManager,
            productRepository: productRepository,
            inventoryChangeRepository: inventoryChangeRepository
        )
        event = updateEvent

        closeFlow()
    }
}
