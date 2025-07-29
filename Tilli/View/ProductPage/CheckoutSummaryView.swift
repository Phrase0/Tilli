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

    @Binding var isPresented: Bool
    @State private var navigateToCashPayment = false
    @State private var navigateToEPayment = false

    @EnvironmentObject var appState: AppState
    @EnvironmentObject var transactionDataManager: TransactionDataManager

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Order Summary")
                        .font(.headline)
                    Spacer()
                    Button(action: {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        isPresented = false
                    }) {
                        Image(systemName: "xmark")
                            .foregroundColor(.gray)
                    }
                }
                .padding()
                
                Divider()
                
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
                                            
                                            let discountedPrice = (item.price * (1 - Double(item.discount) / 100)).rounded()
                                            Text("NT$\(Int(discountedPrice))")
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
                
                HStack {
                    Text("Total")
                        .font(.headline)
                    Spacer()
                    Text("NT$\(totalAmount)")
                        .font(.headline)
                        .bold()
                }
                .padding()
                
                VStack(spacing: 3) {
                    // MARK: - NavigationLink to CashPaymentView
                    if let currentSession = appState.currentSession {
                        NavigationLink(
                            destination: CashPaymentView(
                                totalAmount: totalAmount,
                                session: currentSession,
                                summaryItems: selectedItems
                            ) {
                                isPresented = false
                            }
                                .environmentObject(transactionDataManager)
                                .environmentObject(appState), // optional, if needed inside CashPaymentView
                            isActive: $navigateToCashPayment
                        ) {
                            Text("") // 避免 EmptyView 被忽略
                                .hidden()
                        }
                    }
                    
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
                    
                    // MARK: - NavigationLink to EPaymentView
                    NavigationLink(
                        destination: EPaymentView(totalAmount: totalAmount)
                            .environmentObject(transactionDataManager),
                        isActive: $navigateToEPayment
                    ) {
                        Text("")
                            .hidden()
                    }
                    
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
        }
    }
}
