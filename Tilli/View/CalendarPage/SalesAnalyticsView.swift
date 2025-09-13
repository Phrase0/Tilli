//
//  SalesAnalyticsView.swift
//  Tilli
//
//  Created by Peiyun on 2025/9/8.
//

import SwiftUI

struct SalesAnalyticsView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 48))
                .foregroundColor(.green)
            
            Text("銷售分析")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("此頁面將顯示銷售數據分析")
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}
