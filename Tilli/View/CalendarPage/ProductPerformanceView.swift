//
//  ProductPerformanceView.swift
//  Tilli
//
//  Created by Peiyun on 2025/9/8.
//

import SwiftUI

struct ProductPerformanceView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "chart.bar.fill")
                .font(.system(size: 48))
                .foregroundColor(.blue)
            
            Text("產品績效")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("此頁面將顯示產品銷售績效分析")
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}
