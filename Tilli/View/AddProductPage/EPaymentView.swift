//
//  EPaymentView.swift
//  Tilli
//
//  Created by Peiyun on 2025/7/22.
//

import SwiftUI
import Foundation

struct EPaymentView: View {
    let totalAmount: Decimal

    var body: some View {
        VStack(spacing: 20) {
            Text("E-Payment")
                .font(.largeTitle)
            Text("Total: \(totalAmount.money)")
                .font(.title2)
        }
        .padding()
    }
}
