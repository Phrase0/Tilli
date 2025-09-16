//
//  SessionDetailView.swift
//  Tilli
//
//  Created by Peiyun on 2025/7/5.
//

import SwiftUI

struct SessionDetailView: View {
    
    @EnvironmentObject var productRepository: ProductRepository
    @EnvironmentObject var categoryRepository: CategoryRepository
    @EnvironmentObject var sessionDataManager: SessionDataManager
    @EnvironmentObject var transactionDataManager: TransactionDataManager
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel: SessionDetailViewModel
    
    @Binding var session: SessionModel
    
    @State private var selectedTab: Int = 0
    @State private var checkoutCompleted = false
    @State private var showCheckoutSheet = false
    
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
                        viewModel.productViewModel.loadProducts()
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
    
    private var sessionDetailContent: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 4) {
                Text(viewModel.session.title)
                    .font(.title2)
                    .bold()
                Text("\(viewModel.session.date, formatter: DateFormatter.sessionDate) • NT$\(viewModel.sessionTotalAmount, specifier: "%.0f")")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            .padding(.top)
            
            // 自定義 Picker
            HStack {
                ForEach(0..<2, id: \.self) { index in
                    Button(action: {
                        selectedTab = index
                    }) {
                        VStack(spacing: 6) {
                            Text(index == 0 ? "商品" : "交易明細")
                                .font(.subheadline)
                                .foregroundColor(selectedTab == index ? .blue : .gray)
                                .fontWeight(selectedTab == index ? .semibold : .regular)
                            
                            Rectangle()
                                .fill(selectedTab == index ? Color.blue : Color.clear)
                                .frame(height: 2)
                                .scaleEffect(x: selectedTab == index ? 1.0 : 0.8, y: 1.0)
                                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: selectedTab)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            
            Divider()
            
            TabView(selection: $selectedTab) {
                // 商品頁 - 使用 ProductDetailView
                ProductDetailView(
                    productViewModel: viewModel.productViewModel,
                    session: $session,
                    editingProduct: $editingProduct,
                    showEditProduct: $showEditProduct,
                    showCheckoutSheet: $showCheckoutSheet,
                    checkoutCompleted: $checkoutCompleted
                )
                .tag(0)
                
                // 記錄頁 - 使用 TransactionHistoryView
                TransactionHistoryView(
                    transactionViewModel: viewModel.transactionViewModel,
                    session: $session
                )
                .tag(1)
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
        }
        .background(Color(.systemGroupedBackground))
        .onChange(of: checkoutCompleted) {
//            completed in
//            if completed {
                // 結帳完成後的處理
                viewModel.loadData()
                viewModel.productViewModel.clearAllQuantities()
                viewModel.updateSessionTotalAmount()
                
                // 重置標記
                DispatchQueue.main.async {
                    checkoutCompleted = false
                }
//            }
        }
        .onAppear {
            appState.currentSession = viewModel.session
            viewModel.updateDataManagers(
                transactionDataManager: transactionDataManager,
                sessionDataManager: sessionDataManager,
                productRepository: productRepository,
                categoryRepository: categoryRepository
            )
            viewModel.loadData()
        }
    }
}
