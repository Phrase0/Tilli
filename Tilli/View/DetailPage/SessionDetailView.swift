//
//  SessionDetailView.swift
//  Tilli
//
//  Created by Peiyun on 2025/7/5.
//

import SwiftUI
import Foundation

struct SessionDetailView: View {
    
    @EnvironmentObject var productRepository: ProductRepository
    @EnvironmentObject var sessionDataManager: SessionDataManager
    @EnvironmentObject var transactionDataManager: TransactionDataManager
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel: SessionDetailViewModel

    @Binding var session: SessionModel
    @State private var showingShareSheet = false
    @State private var showClearAlert = false
    
    @State private var selectedTab: Int = 0
    @State private var checkoutCompleted = false
    @State private var showCheckoutSheet = false
    
    @State private var editingProduct: ProductModel? = nil
    @State private var showAddProduct = false

    init(session: Binding<SessionModel>) {
        self._session = session
        self._viewModel = StateObject(wrappedValue: SessionDetailViewModel(session: session))
    }

    var body: some View {
        sessionDetailContent
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(viewModel.session.title)
                        .font(.headline)
                        .foregroundColor(.primary)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    switch selectedTab {
                    case 0: // 商品頁 - 顯示清除按鈕和新增按鈕
                        HStack(spacing: 16) {
                            Button(action: {
                                showClearAlert = true
                            }) {
                                Image(systemName: "trash")
                            }
                            .accessibilityLabel("清除所有已選數量")

                            Button(action: {
                                editingProduct = nil
                                showAddProduct = true
                            }) {
                                Image(systemName: "plus")
                            }
                            .accessibilityLabel("新增產品")
                        }

                    case 1: // 交易明細頁 - 顯示導出按鈕
                        Button(action: {
                            viewModel.exportTabCSV(tabIndex: selectedTab)
                            showingShareSheet = true
                        }) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .disabled(viewModel.isTabExportDisabled(tabIndex: selectedTab))

                    default:
                        EmptyView()
                    }
                }
            }
            .navigationDestination(isPresented: $showAddProduct) {
                AddNewProductView(
                    session: session,
                    productToEdit: editingProduct,
                    onSave: {
                        viewModel.productViewModel.loadProducts()
                    }
                )
            }
    }
    
    private var sessionDetailContent: some View {
        VStack(spacing: 0) {
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
            .padding(.top, 20)
            
            Divider()
            
            TabView(selection: $selectedTab) {
                // 商品頁 - 使用 ProductDetailView
                ProductDetailView(
                    productViewModel: viewModel.productViewModel,
                    session: $session,
                    editingProduct: $editingProduct,
                    showAddProduct: $showAddProduct,
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
                // 結帳完成後的處理
                viewModel.loadData()
                viewModel.productViewModel.clearAllQuantities()
                viewModel.updateSessionTotalAmount()

                // 重置標記
                DispatchQueue.main.async {
                    checkoutCompleted = false
                }
        }
        .onAppear {
            appState.currentSession = viewModel.session
            viewModel.updateDataManagers(
                transactionDataManager: transactionDataManager,
                sessionDataManager: sessionDataManager,
                productRepository: productRepository
            )
            viewModel.loadData()
        }
        .shareSheet(
            isPresented: $showingShareSheet,
            activityItems: { viewModel.currentShareItems },
            excludedTypes: UIActivity.ActivityType.defaultExcludedTypes,
            onComplete: { completed in
                if completed {
                    viewModel.handleCurrentTabExportSuccess()
                }
            }
        )
        .alert("確定要清除所有已選數量嗎？", isPresented: $showClearAlert) {
            Button("取消", role: .cancel) { }
            Button("清除", role: .destructive) {
                viewModel.productViewModel.clearAllQuantities()
            }
        }
    }
}
