//
//  ProductPerformanceView.swift
//  Tilli
//
//  Created by Peiyun on 2025/9/8.
//

import SwiftUI
import Charts
import UniformTypeIdentifiers

struct ProductPerformanceView: View {
    @ObservedObject var productPerformanceViewModel: ProductPerformanceViewModel
    @Binding var session: SessionModel
    @State private var expandedProducts: Set<Int> = []
    @State private var showingShareSheet = false

    init(viewModel: ProductPerformanceViewModel, session: Binding<SessionModel>) {
        self.productPerformanceViewModel = viewModel
        self._session = session
    }
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if productPerformanceViewModel.topProducts.isEmpty && productPerformanceViewModel.categoryAnalysis.isEmpty {
                    EmptyStateView(
                        systemImage: "chart.bar.fill",
                        title: "尚無銷售紀錄",
                        message: "完成結帳後，產品績效會顯示在這裡"
                    )
                } else {
                    VStack(spacing: 24) {
                        // TOP 5 商品榜單
                        topProductsView
                        
                        // 類別銷售彙總
                        categoryAnalysisView
                        
                        // 銷售洞察
                        salesInsightsView
                    }
                }
            }
            .padding()
        }
        
        .onAppear {
            productPerformanceViewModel.loadData()
        }
        .refreshable {
            productPerformanceViewModel.loadData()
        }
        .onChange(of: session.transactions) {
            productPerformanceViewModel.loadData()
        }
        .background(Color(.systemGray6))
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    showingShareSheet = true
                }) {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(productPerformanceViewModel.topProducts.isEmpty && productPerformanceViewModel.categoryAnalysis.isEmpty)
            }
        }
        .alert("CSV 導出成功", isPresented: $productPerformanceViewModel.showingExportAlert) {
            Button("確定") { }
        } message: {
            Text("產品績效報告已成功導出為 CSV 檔案")
        }
        .shareSheet(
            isPresented: $showingShareSheet,
            activityItems: [
                productPerformanceViewModel.createTopProductsCSVFileURL(),
                productPerformanceViewModel.createCategoryAnalysisCSVFileURL()
            ],
            excludedTypes: UIActivity.ActivityType.defaultExcludedTypes,
            onComplete: { completed in
                if completed {
                    productPerformanceViewModel.showExportSuccessAlert()
                }
            }
        )
    }
    
    
    // MARK: - Top Products View
    private var topProductsView: some View {
        VStack(alignment: .leading, spacing: 20) {
            // 熱門商品榜單 Header
            HStack {
                Text("熱門商品榜單")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
            }
            
            VStack(spacing: 16) {
                ForEach(productPerformanceViewModel.topProducts) { product in
                    ProductRankingCard(
                        rank: product.rank,
                        name: product.name,
                        category: product.category,
                        salesCount: product.salesCount,
                        revenue: product.actualRevenue,
                        contributionRate: product.contributionRate,
                        unitPrice: product.unitPrice,
                        originalPrice: product.originalPrice,
                        discount: product.discount,
                        actualRevenue: product.actualRevenue,
                        isExpanded: expandedProducts.contains(product.rank)
                    ) {
                        toggleExpansion(for: product.rank)
                    }
                }
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(12)
    }
    
    // MARK: - Category Analysis View
    private var categoryAnalysisView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("類別銷售彙總")
                .font(.title2)
                .fontWeight(.bold)
            
            VStack(spacing: 16) {
                // Pie Chart
                PieChartView(categories: productPerformanceViewModel.categoryAnalysis)
                    .frame(height: 250)
                
                // Category Details
                VStack(spacing: 8) {
                    ForEach(productPerformanceViewModel.categoryAnalysis) { category in
                        CategoryCard(
                            color: category.color,
                            name: category.name,
                            amount: category.amount,
                            percentage: category.percentage
                        )
                    }
                }
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(12)
    }
    
    // MARK: - Sales Insights View  
    private var salesInsightsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("銷售洞察")
                .font(.title2)
                .fontWeight(.bold)
            
            VStack(spacing: 12) {
                InsightCard(
                    icon: "chart.line.uptrend.xyaxis",
                    iconColor: .blue,
                    title: productPerformanceViewModel.salesInsights.hotProductTitle,
                    description: productPerformanceViewModel.salesInsights.hotProductDescription
                )
                
                InsightCard(
                    icon: "percent",
                    iconColor: .green,
                    title: productPerformanceViewModel.salesInsights.discountTitle,
                    description: productPerformanceViewModel.salesInsights.discountDescription
                )
                
                InsightCard(
                    icon: "lightbulb.fill",
                    iconColor: .orange,
                    title: productPerformanceViewModel.salesInsights.suggestionTitle,
                    description: productPerformanceViewModel.salesInsights.suggestionDescription
                )
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(12)
    }
    
    private func toggleExpansion(for rank: Int) {
        withAnimation(.easeInOut(duration: 0.3)) {
            if expandedProducts.contains(rank) {
                expandedProducts.remove(rank)
            } else {
                expandedProducts.insert(rank)
            }
        }
    }
}
