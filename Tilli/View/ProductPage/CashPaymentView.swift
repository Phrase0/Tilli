//
//  CashPaymentView.swift
//  Tilli
//
//  Created by Peiyun on 2025/7/22.
//

import SwiftUI

struct CashPaymentView: View {
    
    @Environment(\.presentationMode) private var presentationMode
    @Environment(\.dismiss) private var dismiss
    
    @EnvironmentObject var transactionDataManager: TransactionDataManager
    @EnvironmentObject var sessionDataManager: SessionDataManager
    @EnvironmentObject var productDataManager: ProductDataManager
    
    @Binding var session: SessionModel
    
    var onComplete: (SessionModel) -> Void
    
    @ObservedObject var viewModel: CashPaymentViewModel
    
    init(
        totalAmount: Int,
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
                    Text("NT$\(viewModel.totalAmount)")
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
                
                TextField("NT$", text: $viewModel.receivedAmountText)
                    .keyboardType(.numberPad)
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.3)))
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("找零")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Text("NT$\(max(viewModel.change, 0))")
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
                Button(action: {
                    if viewModel.isAmountValid {
                        let updatedSession = viewModel.performCheckout(
                            transactionDataManager: transactionDataManager,
                            sessionDataManager: sessionDataManager, productDataManager: productDataManager
                        )
                        onComplete(updatedSession)
                        dismiss()
                    }
                }) {
                    Text("完成付款")
                        .foregroundColor(.white)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(viewModel.isAmountValid ? Color.blue : Color.gray)
                        .cornerRadius(12)
                }
                .disabled(!viewModel.isAmountValid)
                
                Button("取消") {
                    presentationMode.wrappedValue.dismiss()
                }
                .foregroundColor(.gray)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
            }
        }
        .padding()
    }
}
