//
//  ProductDetailView.swift
//  Tilli
//
//  Created by Peiyun on 2025/8/27.
//

import SwiftUI

struct ProductDetailView: View {
    @ObservedObject var productViewModel: ProductViewModel
    @Binding var session: SessionModel
    @Binding var editingProduct: ProductModel?
    @Binding var showEditProduct: Bool
    @Binding var showCheckoutSheet: Bool
    @Binding var checkoutCompleted: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // 商品列表
            ScrollView {
                let activeCategories = productViewModel.session.categories.filter { !$0.isDisabled }
                let hasAnyProducts = activeCategories.contains { category in
                    !productViewModel.getSortedProductsForCategory(category.id).isEmpty
                }

                if !hasAnyProducts && productViewModel.disabledProducts.isEmpty {
                    // 完全沒有商品時顯示空狀態
                    LazyVStack(spacing: 12) {
                        EmptyStateView(
                            systemImage: "cube.box",
                            title: "尚無商品",
                            message: "請先新增商品後再開始銷售"
                        )
                    }
                } else {
                    VStack(alignment: .leading, spacing: 24) {
                        // 啟用的產品列表
                        ForEach(activeCategories.sorted(by: { $0.createdAt < $1.createdAt }), id: \.id) { category in
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
            }
            
            // Footer - 總計和結帳按鈕
            VStack(spacing: 12) {
                HStack {
                    Text("總計")
                        .font(.headline)
                    Spacer()
                    Text("NT$\(productViewModel.totalAmount())")
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
                        .background(productViewModel.totalAmount() > 0 ? Color.blue : Color.gray)
                        .cornerRadius(30)
                }
                .disabled(productViewModel.totalAmount() == 0)
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .alert(isPresented: $productViewModel.showAlert) {
            productViewModel.createAlert()
        }
        .sheet(isPresented: $showCheckoutSheet) {
            CheckoutSummaryView(
                selectedItems: productViewModel.selectedProductsWithQuantityAndDiscount(),
                totalAmount: productViewModel.totalAmount(),
                session: $session,
                isPresented: $showCheckoutSheet,
                checkoutCompleted: $checkoutCompleted
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
                        Text("NT$\(Int(product.price))")
                            .font(.subheadline)
                            .foregroundColor(isOutOfStock ? .gray : .blue)
                        HStack(spacing: 8) {
                            Text("庫存: \(product.stock)")
                                .font(.caption)
                                .foregroundColor(isOutOfStock ? .gray : .gray)
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
                    }
                    Spacer()
                    Menu {
                        Button {
                            // 進入編輯頁
                            editingProduct = product
                            showEditProduct = true
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
                        ForEach([5, 10, 20], id: \.self) { percent in
                            let isSelected = productViewModel.isDiscountSelected(for: product, percent: percent)
                            Text("\(percent)%")
                                .font(.caption)
                                .padding(.vertical, 4)
                                .padding(.horizontal, 8)
                                .background(isSelected ? Color.blue : Color(.systemGray5))
                                .foregroundColor(isSelected ? .white : (isOutOfStock ? .gray : .primary))
                                .cornerRadius(6)
                                .opacity(isOutOfStock ? 0.6 : 1.0)
                                .onTapGesture {
                                    if !isOutOfStock {
                                        productViewModel.toggleDiscount(for: product, percent: percent)
                                    }
                                }
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
                        Text("NT$\(Int(product.price))")
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
