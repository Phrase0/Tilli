//
//  CashPaymentView.swift
//  Tilli
//
//  Created by Peiyun on 2025/7/22.
//

import SwiftUI
import Foundation

struct CashPaymentView: View {

    @EnvironmentObject var transactionDataManager: TransactionDataManager
    @EnvironmentObject var sessionDataManager: SessionDataManager
    @EnvironmentObject var productRepository: ProductRepository

    @Binding var session: SessionModel

    @Environment(\.closeCheckoutFlow) private var closeFlow

    @ObservedObject var viewModel: CashPaymentViewModel

    // 計算機功能開關
    @AppStorage("calculatorEnabled") private var calculatorEnabled = true

    enum FocusField: Hashable {
        case receivedAmount
    }

    @FocusState private var focusedField: FocusField?

    init(
        totalAmount: Decimal,
        session: Binding<SessionModel>,
        summaryItems: [SummaryItemModel],
        selectedDiscount: DiscountModel? = nil,
        occurredAt: Date? = nil
    ) {
        self._session = session
        self._viewModel = ObservedObject(wrappedValue: CashPaymentViewModel(
            totalAmount: totalAmount,
            session: session.wrappedValue,
            summaryItems: summaryItems,
            selectedDiscount: selectedDiscount,
            occurredAt: occurredAt
        ))
    }

    var body: some View {
        if calculatorEnabled {
            // 完整計算機模式
            calculatorModeView
        } else {
            // 簡化模式：只顯示總金額
            simpleModeView
        }
    }

    // MARK: - 完整計算機模式
    private var calculatorModeView: some View {
        VStack(spacing: 24) {
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

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("支付")
                    .font(.subheadline)
                    .foregroundColor(.gray)

                TextField(viewModel.currencyPlaceholder, text: $viewModel.receivedAmountText)
                    .keyboardType(viewModel.supportsDecimal ? .decimalPad : .numberPad)
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.3)))
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

            VStack(alignment: .leading, spacing: 8) {
                Text("找零")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(max(viewModel.change, 0).money(currency: session.currency))
                    .font(.title)
                    .foregroundColor(.blue)
                    .bold()
                    .frame(maxWidth: .infinity, alignment: .leading)

                Group {
                    if !viewModel.isAmountValid {
                        Label("請輸入等於或大於總額的金額", systemImage: "xmark.octagon.fill")
                            .foregroundColor(.red)
                            .font(.footnote)
                            .multilineTextAlignment(.leading)
                    } else {
                        Color.clear
                            .frame(height: 20)
                    }
                }
            }

            Spacer()

            VStack(spacing: 12) {
                Button {
                    completePayment()
                } label: {
                    Text("完成付款")
                        .foregroundColor(.white)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(viewModel.isAmountValid ? Color.blue : Color.gray)
                        .cornerRadius(12)
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

    // MARK: - 簡化模式（關閉計算機功能）
    private var simpleModeView: some View {
        VStack(spacing: 24) {
            Spacer()

            // 總金額置中顯示
            VStack(spacing: 12) {
                Text("總金額")
                    .font(.title3)
                    .foregroundColor(.gray)

                HStack(spacing: 8) {
                    Image(systemName: "tag.fill")
                        .font(.title)
                        .foregroundColor(.blue)
                    Text(viewModel.totalAmount.money(currency: session.currency))
                        .font(.system(size: 48, weight: .bold))
                        .foregroundColor(.primary)
                }
            }

            Spacer()
            Spacer()
            
            // 完成付款按鈕
            Button {
                completePaymentSimple()
            } label: {
                Text("完成付款")
                    .foregroundColor(.white)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(12)
            }
        }
        .padding()
        .navigationTitle("")
    }

    // MARK: - Helper Methods

    /// 完整模式：需要驗證金額
    private func completePayment() {
        guard viewModel.isAmountValid else { return }

        let updatedSession = viewModel.performCheckout(
            sessionDataManager: sessionDataManager,
            productRepository: productRepository
        )
        session = updatedSession

        // 先收起鍵盤
        focusedField = nil

        // 等鍵盤收起後再關閉整個 flow
//        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
          DispatchQueue.main.async {
            closeFlow()
        }
    }

    /// 簡化模式：直接完成交易
    private func completePaymentSimple() {
        let updatedSession = viewModel.performCheckout(
            sessionDataManager: sessionDataManager,
            productRepository: productRepository
        )
        session = updatedSession
        closeFlow()
    }
}
