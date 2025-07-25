//
//  Untitled.swift
//  Tilli
//
//  Created by Peiyun on 2025/7/5.
//

import SwiftUI

struct SessionDetailView: View {
    @EnvironmentObject var productDataManager: ProductDataManager
    @ObservedObject private var viewModel: SessionDetailViewModel

    @State private var showClearAlert = false
    @State private var showCheckoutSheet = false

    init(session: SessionModel) {
        self._viewModel = ObservedObject(
            wrappedValue: SessionDetailViewModel(session: session)
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 4) {
                Text(viewModel.session.title)
                    .font(.title2)
                    .bold()
                Text("\(viewModel.session.date, formatter: DateFormatter.sessionDate) • NT$\(viewModel.totalAmount())")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            .padding(.top)

            // Tab Toggle
            Picker("", selection: $viewModel.selectedTab) {
                Text("商品").tag(0)
                Text("記錄").tag(1)
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.horizontal)

            Divider()

            TabView(selection: $viewModel.selectedTab) {
                // 商品頁
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        ForEach(viewModel.session.categories, id: \.self) { category in
                            let items = viewModel.products.filter { $0.category == category }
                            if !items.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text(category)
                                        .font(.headline)
                                        .padding(.horizontal)
                                    ForEach(items) { product in
                                        productCard(product)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.top)
                }
                .tag(0)

                // 記錄頁
                VStack {
                    Text("記錄頁內容（尚未實作）")
                        .foregroundColor(.gray)
                        .padding()
                }
                .tag(1)
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))

            // Footer
            VStack(spacing: 12) {
                HStack {
                    Text("總計")
                        .font(.headline)
                    Spacer()
                    Text("NT$\(viewModel.totalAmount())")
                        .font(.headline)
                        .bold()
                }

                Button {
                    showCheckoutSheet = true
                } label: {
                    Text("結帳")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(viewModel.totalAmount() > 0 ? Color.blue : Color.gray)
                        .cornerRadius(30)
                }
                .disabled(viewModel.totalAmount() == 0)
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .toolbar {
            if viewModel.selectedTab == 0 {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showClearAlert = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel("清除所有已選數量")
                }
            }
        }
        .alert("確定要清除所有已選數量嗎？", isPresented: $showClearAlert) {
            Button("取消", role: .cancel) { }
            Button("清除", role: .destructive) {
                viewModel.clearAllQuantities()
            }
        }
        .sheet(isPresented: $showCheckoutSheet) {
            CheckoutSummaryView(
                selectedItems: viewModel.selectedProductsWithQuantityAndDiscount(),
                totalAmount: viewModel.totalAmount(),
                isPresented: $showCheckoutSheet
            )
        }
    }

    private func productCard(_ product: ProductModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(product.name)
                        .font(.headline)
                    Text("NT$\(Int(product.price))")
                        .font(.subheadline)
                        .foregroundColor(.blue)
                    Text("庫存: \(product.stock)")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                Spacer()
                Image(systemName: "ellipsis")
                    .rotationEffect(.degrees(90))
                    .foregroundColor(.gray)
            }
            HStack {
                HStack(spacing: 8) {
                    ForEach([5, 10, 20], id: \.self) { percent in
                        let isSel = viewModel.isDiscountSelected(for: product, percent: percent)
                        Text("\(percent)%")
                            .font(.caption)
                            .padding(4)
                            .background(isSel ? Color.blue : Color(.systemGray5))
                            .foregroundColor(isSel ? .white : .primary)
                            .cornerRadius(4)
                            .onTapGesture {
                                viewModel.toggleDiscount(for: product, percent: percent)
                            }
                    }
                }
                Spacer()
                HStack(spacing: 16) {
                    Button { viewModel.decreaseQuantity(for: product) } label: { Image(systemName: "minus.circle") }
                    Text("\(viewModel.quantity(for: product))")
                        .frame(width: 24)
                    Button { viewModel.increaseQuantity(for: product) } label: { Image(systemName: "plus.circle") }
                }
                .font(.title3)
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(12)
        .shadow(radius: 1, y: 1)
        .padding(.horizontal)
    }
}
