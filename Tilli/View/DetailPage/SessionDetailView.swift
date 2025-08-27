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
                // 商品頁 - 使用 ProductDetailView
                ProductDetailView(
                    viewModel: viewModel,
                    session: $session,
                    editingProduct: $editingProduct,
                    showEditProduct: $showEditProduct,
                    showCheckoutSheet: $showCheckoutSheet,
                    checkoutCompleted: $checkoutCompleted
                )
                .tag(0)
                
                // 記錄頁 - 使用 TransactionHistoryView
                TransactionHistoryView(session: $session)
                    .tag(1)
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
        }
        .background(Color(.systemGroupedBackground))
        .alert(isPresented: $viewModel.showAlert) {
            createAlert()
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
    
    // MARK: - Alert 創建方法
    
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
