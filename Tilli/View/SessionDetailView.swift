//
//  Untitled.swift
//  Tilli
//
//  Created by Peiyun on 2025/7/5.
//

import SwiftUI

struct SessionDetailView: View {
    var session: SessionModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("\(session.title)")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("日期: \(session.date, formatter: DateFormatter.sessionDate)")
                .font(.subheadline)

            Text("狀態: \(session.status.rawValue)")
                .font(.subheadline)

            Text("金額總計: NT$\(session.amount.formatted())")
                .font(.subheadline)

            Divider()

            Text("商品列表")
                .font(.headline)

            ForEach(session.products) { product in
                VStack(alignment: .leading) {
                    Text(product.name)
                        .font(.body)
                        .fontWeight(.semibold)
                    Text("數量: \(product.quantity)  價格: NT$\(product.price, specifier: "%.2f")")
                        .font(.footnote)
                        .foregroundColor(.gray)
                }
                .padding(.vertical, 4)
            }

            Spacer()
        }
        .padding()
        .navigationTitle("場次詳情")
    }
}

