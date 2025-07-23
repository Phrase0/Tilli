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
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Order Summary")
                        .font(.headline)
                    Spacer()
                    Button(action: {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        isPresented = false // 手動關閉 sheet
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
                                            
                                            Text("NT$\(Int(item.price * (1 - Double(item.discount) / 100)))")
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
                
                VStack(spacing: 12) {
                    // NavigationLink to CashPaymentView
                    NavigationLink(destination:
                                    CashPaymentView(totalAmount: totalAmount) {
                        // 付款完成時，關閉 sheet（CheckoutSummaryView）
                        isPresented = false
                    }
                        .environmentObject(appState),
                                   isActive: $navigateToCashPayment
                    ) {
                        EmptyView()
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
                    
                    // NavigationLink to EPaymentView
                    NavigationLink(destination:
                                    EPaymentView(totalAmount: totalAmount)
                        .environmentObject(appState),
                                   isActive: $navigateToEPayment
                    ) {
                        EmptyView()
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
            .navigationBarHidden(true)
        }
    }
}
