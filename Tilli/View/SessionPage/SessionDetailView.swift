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
    
    // 產品刪除相關狀態
    @State private var productToDelete: ProductModel? = nil
    @State private var showDeleteAlert = false
    
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
                        viewModel.loadProducts(using: productDataManager)
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
            .padding(.horizontal)
            
            Divider()
            
            TabView(selection: $selectedTab) {
                // 商品頁
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        ForEach(viewModel.session.categories.filter { !$0.isDisabled }.sorted(by: { $0.createdAt < $1.createdAt }), id: \.id) { category in
                            let items = viewModel.products
                                .filter { $0.categoryId == category.id }
                                .sorted { $0.name < $1.name }
                            if !items.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text(category.name)
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
        .alert("確定要刪除此產品嗎？", isPresented: $showDeleteAlert) {
            Button("取消", role: .cancel) {
                productToDelete = nil
            }
            Button("刪除", role: .destructive) {
                if let product = productToDelete {
                    viewModel.deleteProduct(product, using: productDataManager)
                    productToDelete = nil
                }
            }
        } message: {
            Text("刪除後將無法復原")
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
            viewModel.loadProducts(using: productDataManager)
            viewModel.clearAllQuantities()
            checkoutCompleted = false
        }
        .onAppear {
            appState.currentSession = viewModel.session
            viewModel.loadProducts(using: productDataManager)
            viewModel.updateDataManagers(transactionDataManager: transactionDataManager)
        }
    }
    
    private func productCard(_ product: ProductModel) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if let image = product.image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 60, height: 60)
                    .cornerRadius(8)
                    .clipped()
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
                        Text("NT$\(Int(product.price))")
                            .font(.subheadline)
                            .foregroundColor(.blue)
                        Text("庫存: \(product.stock)")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    Spacer()
                    Menu {
                        Button {
                            // 進入編輯頁 - 設置狀態並觸發條件判斷
                            editingProduct = product
                            showEditProduct = true
                        } label: {
                            Label("編輯", systemImage: "pencil")
                                .frame(minWidth: 60)
                                .multilineTextAlignment(.center)
                        }
                        
                        // 根據是否有交易紀錄決定是否顯示刪除按鈕
                        if !viewModel.hasTransaction(for: product.id) {
                            Button(role: .destructive) {
                                // 設置要刪除的產品並顯示警告
                                productToDelete = product
                                showDeleteAlert = true
                            } label: {
                                Label("刪除", systemImage: "trash")
                                    .frame(minWidth: 60)
                                    .multilineTextAlignment(.center)
                            }
                        }
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
                                .foregroundColor(isSelected ? .white : .primary)
                                .cornerRadius(6)
                                .onTapGesture {
                                    viewModel.toggleDiscount(for: product, percent: percent)
                                }
                        }
                    }
                    Spacer()
                    HStack(spacing: 16) {
                        Button { viewModel.decreaseQuantity(for: product) } label: { Image(systemName: "minus.circle") }
                        Text("\(viewModel.quantity(for: product))").frame(width: 24)
                        Button { viewModel.increaseQuantity(for: product) } label: { Image(systemName: "plus.circle") }
                    }
                    .font(.title3)
                }
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 1, x: 0, y: 1)
        .padding(.horizontal)
    }
}
