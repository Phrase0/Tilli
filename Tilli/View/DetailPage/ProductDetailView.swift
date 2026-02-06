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
                                            if productViewModel.layoutMode == .list {
                                                // 列表模式
                                                ForEach(items) { product in
                                                    productCard(product)
                                                }
                                            } else {
                                                // 網格模式
                                                LazyVGrid(columns: [
                                                    GridItem(.flexible()),
                                                    GridItem(.flexible())
                                                ], spacing: 16) {
                                                    ForEach(items) { product in
                                                        gridProductCard(product)
                                                    }
                                                }
                                                .padding(.horizontal)
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
                                        if productViewModel.layoutMode == .list {
                                            // 列表模式
                                            ForEach(productViewModel.disabledProducts.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) { product in
                                                disabledProductCard(product)
                                            }
                                        } else {
                                            // 網格模式
                                            LazyVGrid(columns: [
                                                GridItem(.flexible()),
                                                GridItem(.flexible())
                                            ], spacing: 16) {
                                                ForEach(productViewModel.disabledProducts.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) { product in
                                                    gridDisabledProductCard(product)
                                                }
                                            }
                                            .padding(.horizontal)
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
        let currentQty = productViewModel.quantity(for: product)
        
        return HStack(alignment: .center, spacing: 12) { // 改為 center 讓對齊更平衡
            // 產品圖片
            SyncableImageView(
                imageData: product.imageData,
                imageURL: product.imageURL,
                entityId: product.id,
                entityType: .product,
                contentMode: .fill
            )
            .frame(width: 70, height: 70)
            .cornerRadius(8)
            .clipped()
            .grayscale(isOutOfStock ? 1.0 : 0.0)
            .opacity(isOutOfStock ? 0.6 : 1.0)

            VStack(alignment: .leading, spacing: 6) {
                // 上半部：名稱與選單
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(product.name)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(isOutOfStock ? .gray : .primary)
                            .lineLimit(1)

                        if let description = product.note, !description.isEmpty {
                            Text(description)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    
                    Menu {
                        Button {
                            editingProduct = product
                            showAddProduct = true
                        } label: {
                            Label("編輯", systemImage: "pencil")
                        }
                        productActionContent(for: product)
                    } label: {
                        Image(systemName: "ellipsis")
                            .rotationEffect(.degrees(90))
                            .foregroundColor(.gray)
                            .padding(4)
                    }
                }

                // 下半部：價格、庫存與數量按鈕
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(MoneyHelper.format(product.price, currencyCode: productViewModel.session.currency))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(isOutOfStock ? .gray : .blue)
                        
                        // 庫存邏輯：無庫存時隱藏文字，改顯示紅色標籤
                        if isOutOfStock {
                            Text("無庫存")
                                .font(.system(size: 12, weight: .regular))
                                .foregroundColor(.red)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.red.opacity(0.1))
                                .cornerRadius(4)
                        } else {
                            Text("庫存: \(product.stock)")
                                .font(.system(size: 12))
                                .foregroundColor(.gray)
                        }
                    }
                    
                    Spacer()

                    // 數量操作區
                    HStack(spacing: 12) {
                        Button {
                            productViewModel.decreaseQuantity(for: product)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.system(size: 22))
                                .foregroundColor(isOutOfStock || currentQty == 0 ? Color(.systemGray4) : .blue.opacity(0.8))
                        }
                        .disabled(isOutOfStock || currentQty == 0)

                        Text("\(currentQty)")
                            .font(.system(size: 14, weight: .medium))
                            .frame(minWidth: 18)
                            .foregroundColor(isOutOfStock ? .gray : .primary)

                        Button {
                            productViewModel.increaseQuantity(for: product)
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 22))
                                .foregroundColor(isOutOfStock || currentQty >= product.stock ? Color(.systemGray4) : .blue.opacity(0.8))
                        }
                        .disabled(isOutOfStock || currentQty >= product.stock)
                    }
                }
            }
        }
        .padding(12)
        .background(isOutOfStock ? Color(.systemGray6) : Color.white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 1, x: 0, y: 1)
        .padding(.horizontal)
        .onTapGesture {
            if isOutOfStock { productViewModel.showOutOfStockAlert(for: product.name) }
        }
    }
    
    // 下架產品卡片
    private func disabledProductCard(_ product: ProductModel) -> some View {
        HStack(alignment: .center, spacing: 12) {
            // 產品圖片
            SyncableImageView(
                imageData: product.imageData,
                imageURL: product.imageURL,
                entityId: product.id,
                entityType: .product,
                contentMode: .fill
            )
            .frame(width: 70, height: 70)
            .cornerRadius(8)
            .clipped()
            .grayscale(1.0)
            .opacity(0.6)
            
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(product.name)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.gray)
                            .lineLimit(1)

                        if let description = product.note, !description.isEmpty {
                            Text(description)
                                .font(.system(size: 12))
                                .foregroundColor(.gray)
                                .lineLimit(1)
                        }
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
                            .padding(4)
                    }
                }

                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(MoneyHelper.format(product.price, currencyCode: productViewModel.session.currency))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.gray)
                        
                        Text("庫存: \(product.stock)")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                    }
                    
                    Spacer()
                    
                    // 保持佔位一致，但顯示禁用狀態
                    HStack(spacing: 12) {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(Color(.systemGray4))
                        Text("0")
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(Color(.systemGray4))
                    }
                }
            }
        }
        .padding(12)
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }
    
    // 網格產品卡片
    private func gridProductCard(_ product: ProductModel) -> some View {
        let isOutOfStock = productViewModel.isOutOfStock(product)
        let currentQty = productViewModel.quantity(for: product)

        return VStack(alignment: .leading, spacing: 0) {
            // MARK: 產品圖片 (1:1 比例)
            SyncableImageView(
                imageData: product.imageData,
                imageURL: product.imageURL,
                entityId: product.id,
                entityType: .product,
                contentMode: .fill
            )
            .aspectRatio(1, contentMode: .fill)
            .frame(minWidth: 0, maxWidth: .infinity)
            .clipped()
            .grayscale(isOutOfStock ? 1.0 : 0.0)
            .opacity(isOutOfStock ? 0.6 : 1.0)

            // MARK: 產品資訊內容
            VStack(alignment: .leading, spacing: 8) {
                // 標題與選單
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(product.name)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(isOutOfStock ? .gray : .primary)
                            .lineLimit(1)

                        if let description = product.note, !description.isEmpty {
                            Text(description)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                    
                    Spacer()

                    Menu {
                        Button {
                            editingProduct = product
                            showAddProduct = true
                        } label: {
                            Label("編輯", systemImage: "pencil")
                        }
                        productActionContent(for: product)
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 14))
                            .rotationEffect(.degrees(90))
                            .foregroundColor(.gray)
                            .padding(4)
                    }
                }

                // 價格
                Text(MoneyHelper.format(product.price, currencyCode: productViewModel.session.currency))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(isOutOfStock ? .gray : .blue)

                Spacer(minLength: 4)

                // MARK: 庫存與數量按鈕並排
                HStack(alignment: .center) {
                    // 庫存顯示區
                        Group {
                            if isOutOfStock {
                                // 無庫存時：隱藏數字，直接顯示紅色警告標籤
                                Text("無庫存")
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundColor(.red)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.red.opacity(0.1))
                                    .cornerRadius(4)
                            } else {
                                // 有庫存時：顯示庫存文字 (size 12)
                                Text("庫存: \(product.stock)")
                                    .font(.system(size: 12))
                                    .foregroundColor(.gray)
                            }
                        }

                    Spacer()

                    // 數量操作區
                    HStack(spacing: 10) {
                        Button {
                            productViewModel.decreaseQuantity(for: product)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.system(size: 22))
                                .foregroundColor(isOutOfStock || currentQty == 0 ? .gray.opacity(0.3) : .blue.opacity(0.8))
                        }
                        .disabled(isOutOfStock || currentQty == 0)

                        Text("\(currentQty)")
                            .font(.system(size: 14, weight: .medium))
                            .frame(minWidth: 18)
                            .foregroundColor(isOutOfStock ? .gray : .primary)

                        Button {
                            productViewModel.increaseQuantity(for: product)
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 22))
                                .foregroundColor(isOutOfStock || currentQty >= product.stock ? .gray.opacity(0.3) : .blue.opacity(0.8))
                        }
                        .disabled(isOutOfStock || currentQty >= product.stock)
                    }
                }
            }
            .padding(10)
        }
        .background(isOutOfStock ? Color(.systemGray6) : Color.white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.06), radius: 3, x: 0, y: 2)
        .onTapGesture {
            if isOutOfStock {
                productViewModel.showOutOfStockAlert(for: product.name)
            }
        }
    }
    
    // 網格下架產品卡片
//    private func gridDisabledProductCard(_ product: ProductModel) -> some View {
//        VStack(alignment: .leading, spacing: 0) {
//            // 產品圖片
//            if let image = product.image {
//                Image(uiImage: image)
//                    .resizable()
//                    .aspectRatio(contentMode: .fill)
//                    .frame(height: 120)
//                    .clipped()
//                    .grayscale(1.0)
//            } else {
//                Rectangle()
//                    .foregroundColor(.clear)
//                    .background(Color(.systemGray5))
//                    .frame(height: 120)
//            }
//
//            VStack(alignment: .leading, spacing: 8) {
//                HStack(alignment: .center) {
//                    VStack(alignment: .leading, spacing: 4) {
//                        Text(product.name)
//                            .font(.headline)
//                            .foregroundColor(.gray)
//                            .lineLimit(1)
//
//                        if let description = product.note, !description.isEmpty {
//                            Text(description)
//                                .font(.caption)
//                                .foregroundColor(.gray)
//                                .lineLimit(1)
//                        }
//                    }
//
//                    Spacer()
//
//                    Menu {
//                        Button("復原") {
//                            productViewModel.handleRestoreAction(for: product.id)
//                        }
//                    } label: {
//                        Image(systemName: "ellipsis")
//                            .rotationEffect(.degrees(90))
//                            .foregroundColor(.gray)
//                            .padding(4)
//                    }
//                }
//
//                Text(MoneyHelper.format(product.price, currencyCode: productViewModel.session.currency))
//                    .font(.subheadline)
//                    .foregroundColor(.gray)
//
//                Text("庫存：\(product.stock)")
//                    .font(.caption)
//                    .foregroundColor(.gray)
//            }
//            .padding(12)
//        }
//        .background(Color(.systemGray6))
//        .cornerRadius(12)
//        .shadow(color: Color.black.opacity(0.05), radius: 1, x: 0, y: 1)
//    }
    private func gridDisabledProductCard(_ product: ProductModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // MARK: 產品圖片 (1:1 比例)
            SyncableImageView(
                imageData: product.imageData,
                imageURL: product.imageURL,
                entityId: product.id,
                entityType: .product,
                contentMode: .fill
            )
            .aspectRatio(1, contentMode: .fill)
            .frame(minWidth: 0, maxWidth: .infinity)
            .clipped()
            .grayscale(1.0)
            .opacity(0.6)

            // MARK: 產品資訊內容
            VStack(alignment: .leading, spacing: 8) {
                // 標題與選單
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(product.name)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.gray)
                            .lineLimit(1)

                        if let description = product.note, !description.isEmpty {
                            Text(description)
                                .font(.caption2)
                                .foregroundColor(.gray)
                                .lineLimit(1)
                        }
                    }
                    
                    Spacer()

                    Menu {
                        Button("復原") {
                            productViewModel.handleRestoreAction(for: product.id)
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 14))
                            .rotationEffect(.degrees(90))
                            .foregroundColor(.gray)
                            .padding(4)
                    }
                }

                // 價格
                Text(MoneyHelper.format(product.price, currencyCode: productViewModel.session.currency))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.gray)

                Spacer(minLength: 4)

                // MARK: 庫存與數量按鈕並排 (禁用狀態)
                HStack(alignment: .center) {
                    // 庫存顯示 (文字大小 12)
                    Text("庫存: \(product.stock)")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)

                    Spacer()

                    // 數量操作區 (純顯示 0，按鈕禁用)
                    HStack(spacing: 10) {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(Color(.systemGray4))

                        Text("0")
                            .font(.system(size: 14, weight: .medium))
                            .frame(minWidth: 18)
                            .foregroundColor(.gray)

                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(Color(.systemGray4))
                    }
                }
            }
            .padding(10)
        }
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 1, x: 0, y: 1)
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
