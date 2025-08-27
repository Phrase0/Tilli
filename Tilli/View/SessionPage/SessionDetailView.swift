//
//  SessionDetailView.swift
//  Tilli
//
//  Created by Peiyun on 2025/7/5.
//

import SwiftUI

struct SessionDetailView: View {
    
    @EnvironmentObject var productDataManager: ProductDataManager
    @EnvironmentObject var transactionDataManager: TransactionDataManager
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel: SessionDetailViewModel
    
    @Binding var session: SessionModel
    
    @State private var showClearAlert = false
    @State private var showCheckoutSheet = false
    @State private var selectedTab: Int = 0
    @State private var checkoutCompleted = false
    
    @State private var editingProduct: ProductModel? = nil
    @State private var showEditProduct = false
    
    init(session: Binding<SessionModel>) {
        self._session = session
        self._viewModel = StateObject(wrappedValue: SessionDetailViewModel(session: session))
    }
    
    var body: some View {
        VStack {
            // 當需要編輯產品時，顯示編輯頁面
            if let product = editingProduct, showEditProduct {
                AddNewProductView(
                    session: session,
                    productToEdit: product,
                    onSave: {
                        // 編輯完成
                        showEditProduct = false
                        editingProduct = nil
                        viewModel.loadProducts()
                    },
                    onCancel: {
                        // 取消編輯
                        showEditProduct = false
                        editingProduct = nil
                    }
                )
            }
            // 否則顯示主要的 SessionDetail 內容
            else {
                sessionDetailContent
            }
        }
        .navigationBarHidden(showEditProduct)
    }
    
    // 將原本的 body 內容提取為 computed property
    private var sessionDetailContent: some View {
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
            Picker("", selection: $selectedTab) {
                Text("商品").tag(0)
                Text("記錄").tag(1)
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(8)
            
            TabView(selection: $selectedTab) {
                // 商品頁
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // 啟用的產品列表
                        ForEach(viewModel.session.categories.filter { !$0.isDisabled }.sorted(by: { $0.createdAt < $1.createdAt }), id: \.id) { category in
                            let items = viewModel.getSortedProductsForCategory(category.id)
                            if !items.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    // 可點擊的分類標題
                                    Button(action: {
                                        viewModel.toggleCategoryExpansion(category.id)
                                    }) {
                                        HStack {
                                            Text(category.name)
                                                .font(.headline)
                                                .foregroundColor(.primary)
                                                .padding(.horizontal)
                                            
                                            Spacer()
                                            
                                            Image(systemName: viewModel.isCategoryExpanded(category.id) ? "chevron.up" : "chevron.down")
                                                .foregroundColor(.gray)
                                                .font(.caption)
                                                .padding(.horizontal)
                                        }
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    
                                    // 商品列表（可展開/收起）
                                    if viewModel.isCategoryExpanded(category.id) {
                                        ForEach(items) { product in
                                            productCard(product)
                                        }
                                    }
                                }
                            }
                        }
                        
                        // 下架商品區
                        if !viewModel.disabledProducts.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Button(action: {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        viewModel.showDisabledProducts.toggle()
                                    }
                                }) {
                                    HStack {
                                        Text("下架商品")
                                            .font(.headline)
                                            .foregroundColor(.gray)
                                            .padding(.horizontal)
                                        
                                        Spacer()
                                        
                                        Image(systemName: viewModel.showDisabledProducts ? "chevron.up" : "chevron.down")
                                            .foregroundColor(.gray)
                                            .font(.caption)
                                            .padding(.horizontal)
                                    }
                                }
                                .buttonStyle(PlainButtonStyle())
                                
                                if viewModel.showDisabledProducts {
                                    ForEach(viewModel.disabledProducts.sorted { $0.name < $1.name }) { product in
                                        disabledProductCard(product)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.top)
                }
                .tag(0)
                
                // 記錄頁
                TransactionHistoryView(session: $session)
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
            if selectedTab == 0 {
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
        .alert(isPresented: $viewModel.showAlert) {
            createAlert()
        }
        .sheet(isPresented: $showCheckoutSheet) {
            CheckoutSummaryView(
                selectedItems: viewModel.selectedProductsWithQuantityAndDiscount(),
                totalAmount: viewModel.totalAmount(),
                session: $session,
                isPresented: $showCheckoutSheet,
                checkoutCompleted: $checkoutCompleted
            )
        }
        .onChange(of: checkoutCompleted) {
            viewModel.loadProducts()
            viewModel.clearAllQuantities()
            checkoutCompleted = false
        }
        .onAppear {
            appState.currentSession = viewModel.session
            // 每次出現時更新資料管理器
            viewModel.updateDataManagers(
                transactionDataManager: transactionDataManager,
                productDataManager: productDataManager
            )
            viewModel.loadProducts()
        }
    }
    
    // MARK: - Helper Methods
    
    // 啟用產品卡片
    private func productCard(_ product: ProductModel) -> some View {
        let isOutOfStock = viewModel.isOutOfStock(product)
        
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
                            let isSelected = viewModel.isDiscountSelected(for: product, percent: percent)
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
                                        viewModel.toggleDiscount(for: product, percent: percent)
                                    }
                                }
                        }
                    }
                    Spacer()
                    HStack(spacing: 16) {
                        Button {
                            if !isOutOfStock {
                                viewModel.decreaseQuantity(for: product)
                            }
                        } label: {
                            Image(systemName: "minus.circle")
                                .foregroundColor(isOutOfStock ? .gray : .blue)
                        }
                        .disabled(isOutOfStock)
                        
                        Text("\(viewModel.quantity(for: product))")
                            .frame(width: 24)
                            .foregroundColor(isOutOfStock ? .gray : .primary)
                        
                        Button {
                            if !isOutOfStock {
                                viewModel.increaseQuantity(for: product)
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
                viewModel.showOutOfStockAlert(for: product.name)
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
                            viewModel.handleRestoreAction(for: product.id)
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
        switch viewModel.getActionType(for: product.id) {
        case .disable:
            Button {
                viewModel.handleDisableAction(for: product.id)
            } label: {
                Label("下架", systemImage: "minus.circle")
            }
        case .delete:
            Button(role: .destructive) {
                viewModel.handleDeleteAction(for: product.id)
            } label: {
                Label("刪除", systemImage: "trash")
            }
        }
    }
    
    // Alert 創建方法
    private func createAlert() -> Alert {
        if viewModel.productPendingRestore != nil {
            // 復原操作的警告
            return Alert(
                title: Text("確認復原"),
                message: Text("確定要復原此產品嗎？"),
                primaryButton: .default(Text("確認")) {
                    viewModel.confirmRestoreAction()
                },
                secondaryButton: .cancel {
                    viewModel.cancelRestoreAction()
                }
            )
        } else if viewModel.productPendingDeletion != nil {
            if viewModel.isDisableAction {
                // 下架操作的警告
                return Alert(
                    title: Text("確認下架"),
                    message: Text(viewModel.alertMessage),
                    primaryButton: .default(Text("確認")) {
                        viewModel.confirmDeletionAction()
                    },
                    secondaryButton: .cancel {
                        viewModel.cancelDeletionAction()
                    }
                )
            } else {
                // 刪除操作的警告
                return Alert(
                    title: Text("確認刪除"),
                    message: Text(viewModel.alertMessage),
                    primaryButton: .destructive(Text("刪除")) {
                        viewModel.confirmDeletionAction()
                    },
                    secondaryButton: .cancel {
                        viewModel.cancelDeletionAction()
                    }
                )
            }
        } else {
            return Alert(
                title: Text("提醒"),
                message: Text(viewModel.alertMessage),
                dismissButton: .default(Text("好"))
            )
        }
    }
}
