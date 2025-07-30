//
//  EPaymentView.swift
//  Tilli
//
//  Created by Peiyun on 2025/7/22.
//

import SwiftUI

struct EPaymentView: View {
    let totalAmount: Int

    var body: some View {
        VStack(spacing: 20) {
            Text("E-Payment")
                .font(.largeTitle)
            Text("Total: NT$\(totalAmount)")
                .font(.title2)
        }
        .padding()
    }
}
