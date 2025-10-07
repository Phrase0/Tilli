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
    let session: SessionModel

    var body: some View {
        VStack(spacing: 20) {
            Text("E-Payment")
                .font(.largeTitle)
            Text("Total: \(totalAmount.money(currency: session.currency))")
                .font(.title2)
        }
        .padding()
    }
}
