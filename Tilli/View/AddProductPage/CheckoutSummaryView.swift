//
// CheckoutSummaryView.swift
//  Tilli
//
//  Created by Peiyun on 2025/7/13.
//

import SwiftUI

struct CheckoutSummaryView: View {
    let selectedItems: [SummaryItemModel]
    let totalAmount: Int

    @Binding var session: SessionModel
    @Binding var isPresented: Bool
    @Binding var checkoutCompleted: Bool

    @State private var navigateToCashPayment = false
    @State private var navigateToEPayment = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // MARK: Header
                HStack {
                    Text("Order Summary")
                        .font(.headline)
                    Spacer()
                    Button {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundColor(.gray)
                    }
                }
                .padding()

                Divider()

                // MARK: 商品清單
                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(selectedItems) { item in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.name)
                                        .font(.body)

                                    HStack(spacing: 8) {
                                        Text("Qty: \(item.quantity)")
                                            .font(.caption)
                                            .foregroundColor(.gray)

                                        if item.discount > 0 {
                                            Text("\(item.discount)%")
                                                .font(.caption)
                                                .padding(4)
                                                .background(Color.blue.opacity(0.2))
                                                .cornerRadius(4)

                                            let discountedPrice = Int((item.price * (1 - Double(item.discount) / 100)).rounded())
                                            Text("NT$\(discountedPrice)")
                                                .font(.caption)
                                                .foregroundColor(.gray)
                                        } else {
                                            Text("NT$\(Int(item.price))")
                                                .font(.caption)
                                                .foregroundColor(.gray)
                                        }
                                    }
                                }

                                Spacer()

                                Text("NT$\(Int(item.total))")
                                    .font(.body)
                                    .fontWeight(.semibold)
                            }
                        }
                    }
                    .padding()
                }

                Divider()

                // MARK: 總金額
                HStack {
                    Text("Total")
                        .font(.headline)
                    Spacer()
                    Text("NT$\(totalAmount)")
                        .font(.headline)
                        .bold()
                }
                .padding()

                // MARK: 支付方式
                VStack(spacing: 8) {
                    // 現金付款
                    Button {
                        navigateToCashPayment = true
                    } label: {
                        HStack {
                            Image(systemName: "banknote")
                            VStack(alignment: .leading) {
                                Text("Cash Payment")
                                Text("Pay with cash")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            Spacer()
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    }

                    // 電子支付
                    Button {
                        navigateToEPayment = true
                    } label: {
                        HStack {
                            Image(systemName: "creditcard")
                            VStack(alignment: .leading) {
                                Text("E-Payment")
                                Text("Pay with digital wallet")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            Spacer()
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    }
                }
                .padding()
            }
            // MARK: - Navigation Destinations
            .navigationDestination(isPresented: $navigateToCashPayment) {
                CashPaymentView(
                    totalAmount: totalAmount,
                    session: $session,
                    summaryItems: selectedItems
                ) { updatedSession in
                    self.session = updatedSession
                    checkoutCompleted = true
                    isPresented = false
                }
            }
            .navigationDestination(isPresented: $navigateToEPayment) {
                EPaymentView(totalAmount: totalAmount)
            }
        }
    }
}
