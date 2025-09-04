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
            
            // Tab Toggle
            Picker("", selection: $selectedTab) {
                Text("商品").tag(0)
                Text("交易明細").tag(1)
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(8)
            
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
            viewModel.productViewModel.loadProducts()
            viewModel.productViewModel.clearAllQuantities()
            checkoutCompleted = false
        }
        .onAppear {
            appState.currentSession = viewModel.session
            // 每次出現時更新資料管理器
            viewModel.updateDataManagers(
                transactionDataManager: transactionDataManager,
                sessionDataManager: sessionDataManager,
                productRepository: productRepository,
                categoryRepository: categoryRepository
            )
            viewModel.productViewModel.loadProducts()
        }
    }
}
