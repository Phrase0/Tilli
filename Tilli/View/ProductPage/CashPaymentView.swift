//
//  CashPaymentView.swift
//  Tilli
//
//  Created by Peiyun on 2025/7/22.
//

import SwiftUI

struct CashPaymentView: View {
    var totalAmount: Int // e.g. 4599 表示 NT$4599
    var onComplete: () -> Void
    
    @Environment(\.presentationMode) private var presentationMode
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var receivedAmountText: String = ""
    @State private var errorMessage: String? = nil

    private var receivedAmount: Int {
        Int(receivedAmountText) ?? 0
    }

    private var change: Int {
        receivedAmount - totalAmount
    }

    private var isAmountValid: Bool {
        receivedAmount >= totalAmount
    }

    var body: some View {
        VStack(spacing: 24) {
            // 標題區
            VStack(spacing: 8) {
                Text("Total Amount Due")
                    .font(.subheadline)
                    .foregroundColor(.gray)

                HStack(spacing: 4) {
                    Image(systemName: "tag.fill")
                        .foregroundColor(.blue)
                    Text("NT$\(totalAmount)")
                        .font(.largeTitle)
                        .bold()
                        .foregroundColor(.black)
                }
            }

            Divider()

            // 收到金額輸入
            VStack(alignment: .leading, spacing: 8) {
                Text("Amount Received")
                    .font(.subheadline)
                    .foregroundColor(.gray)

                TextField("NT$", text: $receivedAmountText)
                    .keyboardType(.numberPad)
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.3)))
            }

            // 找零金額
            VStack(alignment: .leading, spacing: 8) {
                Text("Change Due")
                    .font(.subheadline)
                    .foregroundColor(.gray)

                Text("NT$\(max(change, 0))")
                    .font(.title)
                    .foregroundColor(.blue)
                    .bold()

                if !isAmountValid {
                    Label("Please enter an amount equal to or greater than the total", systemImage: "xmark.octagon.fill")
                        .foregroundColor(.red)
                        .font(.footnote)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()

            // 按鈕區
            VStack(spacing: 12) {
                Button(action: {
                    if isAmountValid {
                        // 儲存目前 summary 為一筆交易紀錄
                        appState.transactionRecords.append(appState.currentSummaryItems)
                        
                        // 根據 summary 扣除產品庫存，且更新 AppState.sessions
                        if let currentSessionId = appState.currentSession?.id {
                            if let sessionIndex = appState.sessions.firstIndex(where: { $0.id == currentSessionId }) {
                                // 先把該 session 取出，因為 struct 是值類型
                                var updatedSession = appState.sessions[sessionIndex]
                                
                                for item in appState.currentSummaryItems {
                                    if let productIndex = updatedSession.products.firstIndex(where: { $0.id == item.product.id }) {
                                        // 扣除庫存
                                        updatedSession.products[productIndex].stock -= item.quantity
                                        
                                        // 確保庫存不會小於0
                                        if updatedSession.products[productIndex].stock < 0 {
                                            updatedSession.products[productIndex].stock = 0
                                        }
                                    }
                                }
                                
                                // 把更新後的 session 存回 AppState.sessions
                                appState.sessions[sessionIndex] = updatedSession
                                
                                // 同時更新 currentSession (避免 UI 不同步)
                                appState.currentSession = updatedSession
                            }
                        }
                        
                        // 清空目前購物車
                        appState.currentSummaryItems = []
                        
                        // 返回前兩層（CheckoutSummaryView & SessionDetailView）
                        onComplete()
                        dismiss()
                    }
                }) {
                    Text("Complete Payment")
                        .foregroundColor(.white)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(isAmountValid ? Color.blue : Color.gray)
                        .cornerRadius(12)
                }
                .disabled(!isAmountValid)

                Button("Cancel") {
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
