//
//  ProductDetailView.swift
//  Tilli
//
//  Created by Peiyun on 2025/8/27.
//

import SwiftUI
import Foundation

struct ProductDetailView: View {
    @ObservedObject var productViewModel: ProductViewModel
    @Binding var session: SessionModel
    @Binding var editingProduct: ProductModel?
    @Binding var showAddProduct: Bool
    @Binding var showCheckoutSheet: Bool
    @Binding var checkoutCompleted: Bool

    var body: some View {
        Group {
            if productViewModel.shouldShowEmptyState {
                // 完全沒有商品時顯示空狀態
                ScrollView {
                    VStack(spacing: 24) {
                        EmptyStateView(
                            systemImage: "cube.box",
                            title: "尚無商品",
                            message: "請先新增商品後再開始銷售",
                            topPadding: 90
                        )

                        Button {
                            editingProduct = nil
                            showAddProduct = true
                        } label: {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                Text("新增產品")
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.horizontal, 32)
                            .padding(.vertical, 14)
                            .background(Color.blue)
                            .cornerRadius(25)
                        }
                    }
                }
            } else {
                // 有商品時顯示正常的商品列表和結帳功能
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            // 啟用的產品列表
                            ForEach(productViewModel.session.categories.filter { !$0.isDisabled }.sorted(by: { $0.sortOrder < $1.sortOrder }), id: \.id) { category in
                                let items = productViewModel.getSortedProductsForCategory(category.id)
                                if !items.isEmpty {
                                    VStack(alignment: .leading, spacing: 12) {
                                        // 可點擊的分類標題
                                        Button(action: {
                                            productViewModel.toggleCategoryExpansion(category.id)
                                        }) {
                                            HStack {
                                                Text(category.name)
                                                    .font(.headline)
                                                    .foregroundColor(.primary)
                                                    .padding(.horizontal)
                                                
                                                Spacer()
                                                
                                                Image(systemName: productViewModel.isCategoryExpanded(category.id) ? "chevron.up" : "chevron.down")
                                                    .foregroundColor(.gray)
                                                    .font(.caption)
                                                    .padding(.horizontal)
                                            }
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                        
                                        // 商品列表（可展開/收起）
                                        if productViewModel.isCategoryExpanded(category.id) {
                                            ForEach(items) { product in
                                                productCard(product)
                                            }
                                        }
                                    }
                                }
                            }
                            
                            // 下架商品區
                            if !productViewModel.disabledProducts.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    Button(action: {
                                        withAnimation(.easeInOut(duration: 0.3)) {
                                            productViewModel.showDisabledProducts.toggle()
                                        }
                                    }) {
                                        HStack {
                                            Text("下架商品")
                                                .font(.headline)
                                                .foregroundColor(.gray)
                                                .padding(.horizontal)
                                            
                                            Spacer()
                                            
                                            Image(systemName: productViewModel.showDisabledProducts ? "chevron.up" : "chevron.down")
                                                .foregroundColor(.gray)
                                                .font(.caption)
                                                .padding(.horizontal)
                                        }
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    
                                    if productViewModel.showDisabledProducts {
                                        ForEach(productViewModel.disabledProducts.sorted { $0.name < $1.name }) { product in
                                            disabledProductCard(product)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.top)
                    }
                    
                    // Footer - 折扣選擇器、總計和結帳按鈕
                    VStack(spacing: 12) {
                        // 折扣選擇器（只在有折扣選項時顯示）
                        if !productViewModel.session.discounts.isEmpty {
                            HStack(spacing: 12) {
                                Text("折扣")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)

                                Menu {
                                    // 無折扣選項
                                    Button {
                                        productViewModel.selectedDiscountId = nil
                                    } label: {
                                        HStack {
                                            Text("- -")
                                            if productViewModel.selectedDiscountId == nil {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }

                                    // 各個折扣選項
                                    ForEach(productViewModel.session.discounts) { discount in
                                        Button {
                                            productViewModel.selectedDiscountId = discount.id
                                        } label: {
                                            HStack {
                                                Text(discount.displayText(currency: productViewModel.session.currency))
                                                if productViewModel.selectedDiscountId == discount.id {
                                                    Image(systemName: "checkmark")
                                                }
                                            }
                                        }
                                    }
                                } label: {
                                    HStack {
                                        // 靠右對齊
                                        Spacer()
                                        Text(productViewModel.selectedDiscount?.displayText(currency: productViewModel.session.currency) ?? "- -")
                                            .font(.subheadline)
                                            .foregroundColor(.primary)
                                        Image(systemName: "chevron.up.chevron.down")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .frame(maxWidth: .infinity)
                                    .background(Color.white)
                                    .cornerRadius(8)
                                }
                            }
                        }

                        // 折扣超過上限的提示
                        if let warning = productViewModel.discountWarningMessage {
                            HStack {
                                Spacer()
                                Image(systemName: "info.circle")
                                    .foregroundColor(.orange)
                                Text(warning)
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }

                        HStack {
                            Text("總計")
                                .font(.headline)
                            Spacer()
                            Text(MoneyHelper.format(productViewModel.totalAmount(), currencyCode: productViewModel.session.currency))
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
                                .background(productViewModel.subtotal() > 0 ? Color.blue : Color.gray)
                                .cornerRadius(30)
                        }
                        .disabled(productViewModel.subtotal() == 0)
                    }
                    .padding()
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .alert(isPresented: $productViewModel.showAlert) {
            productViewModel.createAlert()
        }
        .sheet(isPresented: $showCheckoutSheet) {
            CheckoutFlowView(
                isPresented: $showCheckoutSheet,
                checkoutCompleted: $checkoutCompleted,
                session: $session,
                selectedItems: productViewModel.selectedProductsWithQuantity(),
                totalAmount: productViewModel.totalAmount(),
                selectedDiscount: productViewModel.effectiveDiscount()
            )
        }
    }
    
    // MARK: - Helper Methods
    
    // 啟用產品卡片
    private func productCard(_ product: ProductModel) -> some View {
        let isOutOfStock = productViewModel.isOutOfStock(product)
        
        return HStack(alignment: .top, spacing: 12) {
            if let image = product.image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 60, height: 60)
                    .cornerRadius(8)
                    .clipped()
                    .grayscale(isOutOfStock ? 1.0 : 0.0)
                    .opacity(isOutOfStock ? 0.6 : 1.0)
            } else {
                Rectangle()
                    .foregroundColor(.clear)
                    .background(Color(.systemGray5))
                    .frame(width: 60, height: 60)
                    .cornerRadius(8)
                    .clipped()
                    .opacity(isOutOfStock ? 0.6 : 1.0)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(product.name)
                            .font(.headline)
                            .foregroundColor(isOutOfStock ? .gray : .primary)
                        Text(MoneyHelper.format(product.price, currencyCode: productViewModel.session.currency))
                            .font(.subheadline)
                            .foregroundColor(isOutOfStock ? .gray : .blue)
                    }
                    Spacer()
                    Menu {
                        Button {
                            // 進入編輯頁
                            editingProduct = product
                            showAddProduct = true
                        } label: {
                            Label("編輯", systemImage: "pencil")
                        }

                        // 根據產品狀態顯示不同的操作按鈕
                        productActionContent(for: product)
                    } label: {
                        Image(systemName: "ellipsis")
                            .rotationEffect(.degrees(90))
                            .foregroundColor(.gray)
                            .padding(8)
                    }
                }

                HStack {
                    HStack(spacing: 8) {
                        Text("庫存: \(product.stock)")
                            .font(.caption)
                            .foregroundColor(.gray)
                        if isOutOfStock {
                            Text("無庫存")
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.red.opacity(0.1))
                                .foregroundColor(.red)
                                .cornerRadius(4)
                        }
                    }

                    Spacer()

                    HStack(spacing: 16) {
                        Button {
                            if !isOutOfStock {
                                productViewModel.decreaseQuantity(for: product)
                            }
                        } label: {
                            Image(systemName: "minus.circle")
                                .foregroundColor(isOutOfStock ? .gray : .blue)
                        }
                        .disabled(isOutOfStock)

                        Text("\(productViewModel.quantity(for: product))")
                            .frame(width: 24)
                            .foregroundColor(isOutOfStock ? .gray : .primary)

                        Button {
                            if !isOutOfStock {
                                productViewModel.increaseQuantity(for: product)
                            }
                        } label: {
                            Image(systemName: "plus.circle")
                                .foregroundColor(isOutOfStock ? .gray : .blue)
                        }
                        .disabled(isOutOfStock)
                    }
                    .font(.title3)
                    .opacity(isOutOfStock ? 0.6 : 1.0)
                }
            }
        }
        .padding()
        .background(isOutOfStock ? Color(.systemGray6) : Color.white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 1, x: 0, y: 1)
        .padding(.horizontal)
        .opacity(isOutOfStock ? 0.6 : 1.0)
        .onTapGesture {
            if isOutOfStock {
                // 點擊無庫存商品時給予提示
                productViewModel.showOutOfStockAlert(for: product.name)
            }
        }
    }
    
    // 下架產品卡片
    private func disabledProductCard(_ product: ProductModel) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if let image = product.image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 60, height: 60)
                    .cornerRadius(8)
                    .clipped()
                    .grayscale(1.0) // 灰階效果
            } else {
                Rectangle()
                    .foregroundColor(.clear)
                    .background(Color(.systemGray5))
                    .frame(width: 60, height: 60)
                    .cornerRadius(8)
                    .clipped()
            }
            
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(product.name)
                            .font(.headline)
                            .foregroundColor(.gray)
                        Text(MoneyHelper.format(product.price, currencyCode: productViewModel.session.currency))
                            .font(.subheadline)
                            .foregroundColor(.gray)
                        Text("庫存: \(product.stock)")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    Spacer()
                    Menu {
                        Button("復原") {
                            productViewModel.handleRestoreAction(for: product.id)
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .rotationEffect(.degrees(90))
                            .foregroundColor(.gray)
                            .padding(8)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 1, x: 0, y: 1)
        .padding(.horizontal)
    }
    
    @ViewBuilder
    private func productActionContent(for product: ProductModel) -> some View {
        switch productViewModel.getActionType(for: product.id) {
        case .disable:
            Button {
                productViewModel.handleDisableAction(for: product.id)
            } label: {
                Label("下架", systemImage: "minus.circle")
            }
        case .delete:
            Button(role: .destructive) {
                productViewModel.handleDeleteAction(for: product.id)
            } label: {
                Label("刪除", systemImage: "trash")
            }
        }
    }
}
