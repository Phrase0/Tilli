//
//  CashPaymentView.swift
//  Tilli
//
//  Created by Peiyun on 2025/7/22.
//

import SwiftUI

struct CashPaymentView: View {
    var totalAmount: Int // e.g. 4599 表示 NT$4599
    @Environment(\.presentationMode) private var presentationMode

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
                }
            }

            Spacer()

            // 按鈕區
            VStack(spacing: 12) {
                Button(action: {
                    // 完成付款
                    if isAmountValid {
                        // 實際付款邏輯處理
                        print("付款完成，找零：NT$\(change)")
                        presentationMode.wrappedValue.dismiss()
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
