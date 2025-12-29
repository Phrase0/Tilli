//
//  EPaymentView.swift
//  Tilli
//
//  Created by Peiyun on 2025/7/22.
//

import SwiftUI
import Foundation

struct EPaymentView: View {

    @EnvironmentObject var transactionDataManager: TransactionDataManager
    @EnvironmentObject var sessionDataManager: SessionDataManager
    @EnvironmentObject var productRepository: ProductRepository
    @EnvironmentObject var qrCodeDataManager: QRCodeDataManager

    @Binding var session: SessionModel

    @Environment(\.closeCheckoutFlow) private var closeFlow

    @ObservedObject var viewModel: EPaymentViewModel

    init(
        totalAmount: Decimal,
        session: Binding<SessionModel>,
        summaryItems: [SummaryItemModel],
        selectedDiscount: DiscountModel? = nil
    ) {
        self._session = session
        self._viewModel = ObservedObject(wrappedValue: EPaymentViewModel(
            totalAmount: totalAmount,
            session: session.wrappedValue,
            summaryItems: summaryItems,
            selectedDiscount: selectedDiscount
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            // 總金額顯示
            VStack(spacing: 8) {
                Text("總金額")
                    .font(.subheadline)
                    .foregroundColor(.gray)

                HStack(spacing: 4) {
                    Image(systemName: "tag.fill")
                        .foregroundColor(.blue)
                    Text(viewModel.totalAmount.money(currency: session.currency))
                        .font(.largeTitle)
                        .bold()
                        .foregroundColor(.black)
                }
            }
            .padding(.top, 24)
            .padding(.bottom, 16)

            Divider()

            // QR Code Section
            VStack(spacing: 24) {
                Spacer()

                // QR Code Container
                ZStack {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.white)
                        .frame(width: 280, height: 280)
                        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 6)

                    if let qrImage = qrCodeDataManager.qrCodeImage {
                        Image(uiImage: qrImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 260, height: 260)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    } else {
                        VStack(spacing: 16) {
                            Image(systemName: "qrcode")
                                .font(.system(size: 80))
                                .foregroundColor(.gray.opacity(0.3))

                            VStack(spacing: 6) {
                                Text("尚未設定收款碼")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(.gray)
                                Text("請至「我的收款碼」頁面新增")
                                    .font(.system(size: 14))
                                    .foregroundColor(.gray.opacity(0.7))
                            }
                        }
                    }
                }

                Spacer()
            }

            // 完成付款按鈕
            VStack(spacing: 12) {
                Button(action: {
                    completePayment()
                }) {
                    Text("完成付款")
                        .foregroundColor(.white)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(qrCodeDataManager.qrCodeImage != nil ? Color.blue : Color.gray)
                        .cornerRadius(12)
                }
                .disabled(qrCodeDataManager.qrCodeImage == nil)
            }
        }
        .padding()
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Helper Methods

    private func completePayment() {
        guard qrCodeDataManager.qrCodeImage != nil else { return }

        let updatedSession = viewModel.performCheckout(
            sessionDataManager: sessionDataManager,
            productRepository: productRepository
        )
        session = updatedSession

        // 電子支付無鍵盤，直接關閉整個 flow
        closeFlow()
    }
}
