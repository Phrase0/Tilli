//
//  Untitled.swift
//  Tilli
//
//  Created by Peiyun on 2025/7/5.
//

import SwiftUI

struct SessionDetailView: View {
    var session: SessionModel

    @State private var quantities: [UUID: Int] = [:]
    @State private var selectedTab: Int = 0 // 0: 商品, 1: 記錄

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 4) {
                Text(session.title)
                    .font(.title2)
                    .bold()

                Text("\(session.date, formatter: DateFormatter.sessionDate) • NT$\(session.amount)")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            .padding(.top)

            // 分頁 Tab 指示器
            Picker("", selection: $selectedTab) {
                Text("商品").tag(0)
                Text("記錄").tag(1)
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.horizontal)

            Divider()

            TabView(selection: $selectedTab) {
                // 商品頁
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        ForEach(session.categories, id: \.self) { category in
                            let productsInCategory = session.products.filter { $0.category == category }

                            if !productsInCategory.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("\(category)")
                                        .font(.headline)
                                        .padding(.horizontal)

                                    ForEach(productsInCategory) { product in
                                        productCard(product)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.top)
                }
                .tag(0)

                // 記錄頁（佔位）
                VStack {
                    Text("記錄頁內容（尚未實作）")
                        .foregroundColor(.gray)
                        .padding()
                }
                .tag(1)
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))

            // Footer: 總計與結帳
            VStack(spacing: 12) {
                HStack {
                    Text("總計")
                        .font(.headline)
                    Spacer()
                    Text("NT$\(totalAmount())")
                        .font(.headline)
                        .bold()
                }

                Button(action: {
                    // 處理結帳邏輯（可留空）
                }) {
                    Text("結帳")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(30)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }

    // 商品卡片
    @ViewBuilder
    private func productCard(_ product: ProductModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(product.name)
                        .font(.headline)

                    Text("NT$\(Int(product.price))")
                        .font(.subheadline)
                        .foregroundColor(.blue)

                    Text("庫存: \(product.quantity)")
                        .font(.caption)
                        .foregroundColor(.gray)
                }

                Spacer()

                Image(systemName: "ellipsis")
                    .rotationEffect(.degrees(90))
                    .foregroundColor(.gray)
            }

            // 折扣與數量在同一列
            HStack {
                HStack(spacing: 8) {
                    ForEach([5, 10, 20], id: \.self) { percent in
                        Text("\(percent)%")
                            .font(.caption)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .background(Color(.systemGray5))
                            .cornerRadius(6)
                    }
                }

                Spacer()

                HStack(spacing: 16) {
                    Button(action: {
                        quantities[product.id, default: 0] = max(0, quantities[product.id, default: 0] - 1)
                    }) {
                        Image(systemName: "minus.circle")
                    }

                    Text("\(quantities[product.id, default: 0])")
                        .frame(width: 24)

                    Button(action: {
                        quantities[product.id, default: 0] += 1
                    }) {
                        Image(systemName: "plus.circle")
                    }
                }
                .font(.title3)
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 1, x: 0, y: 1)
        .padding(.horizontal)
    }

    // 計算總額
    private func totalAmount() -> Int {
        session.products.reduce(0) { result, product in
            let qty = quantities[product.id, default: 0]
            return result + Int(product.price) * qty
        }
    }
}
