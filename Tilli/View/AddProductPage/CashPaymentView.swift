//
//  CashPaymentView.swift
//  Tilli
//
//  Created by Peiyun on 2025/7/22.
//

import SwiftUI
import Foundation

struct CashPaymentView: View {

    @Environment(\.presentationMode) private var presentationMode
    @Environment(\.dismiss) private var dismiss

    @EnvironmentObject var transactionDataManager: TransactionDataManager
    @EnvironmentObject var sessionDataManager: SessionDataManager
    @EnvironmentObject var productRepository: ProductRepository

    @Binding var session: SessionModel

    var onComplete: (SessionModel) -> Void

    @ObservedObject var viewModel: CashPaymentViewModel

    enum FocusField: Hashable {
        case receivedAmount
    }

    @FocusState private var focusedField: FocusField?
    
    init(
        totalAmount: Decimal,
        session: Binding<SessionModel>,
        summaryItems: [SummaryItemModel],
        onComplete: @escaping (SessionModel) -> Void
    ) {
        self._session = session
        self._viewModel = ObservedObject(wrappedValue: CashPaymentViewModel(
            totalAmount: totalAmount,
            session: session.wrappedValue,
            summaryItems: summaryItems
        ))
        self.onComplete = onComplete
    }
    
    var body: some View {
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
                        if viewModel.isAmountValid {
                            let updatedSession = viewModel.performCheckout(
                                sessionDataManager: sessionDataManager,
                                productRepository: productRepository
                            )
                            session = updatedSession
                            onComplete(updatedSession)
                            dismiss()
                        }
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
                        // 這個 Spacer 是重點：當錯誤不顯示時，保留空間
                        Color.clear
                            .frame(height: 20) // 要與錯誤訊息大致等高
                    }
                }
            }
            
            Spacer()
            
            VStack(spacing: 12) {
                Button {
                    if viewModel.isAmountValid {
                        let updatedSession = viewModel.performCheckout(
                            sessionDataManager: sessionDataManager,
                            productRepository: productRepository
                        )
                        session = updatedSession  // 直接更新 Binding
                        onComplete(updatedSession)
                        dismiss()
                    }
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
            // 自動聚焦到金額輸入欄位
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.focusedField = .receivedAmount
            }
        }
    }
}
