//
//  ProductPerformanceView.swift
//  Tilli
//
//  Created by Peiyun on 2025/9/8.
//

import SwiftUI
import Charts

struct ProductPerformanceView: View {
    @ObservedObject var viewModel: ProductPerformanceViewModel
    @State private var expandedProducts: Set<Int> = []
    
    init(viewModel: ProductPerformanceViewModel) {
        self.viewModel = viewModel
    }
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if viewModel.isLoading {
                    ProgressView("載入中...")
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else if viewModel.topProducts.isEmpty && viewModel.categoryAnalysis.isEmpty {
                    // 空狀態
                    VStack(spacing: 16) {
                        Image(systemName: "chart.bar.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.gray)
                        
                        Text("尚無銷售紀錄")
                            .font(.headline)
                            .foregroundColor(.gray)
                        
                        Text("完成結帳後，產品績效會顯示在這裡")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 100)
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
        .background(Color(.systemGray6))
        .refreshable {
            viewModel.loadData()
        }
    }
    
    
    // MARK: - Top Products View
    private var topProductsView: some View {
        VStack(alignment: .leading, spacing: 20) {
            // TOP 5 商品榜單 Header
            HStack {
                Text("TOP 5 商品榜單")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
            }
            
            VStack(spacing: 16) {
                ForEach(viewModel.topProducts) { product in
                    ProductRankingCard(
                        rank: product.rank,
                        name: product.name,
                        category: product.category,
                        salesCount: product.salesCount,
                        revenue: product.revenue,
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
                PieChartView(categories: viewModel.categoryAnalysis)
                    .frame(height: 250)
                
                // Category Details
                VStack(spacing: 8) {
                    ForEach(viewModel.categoryAnalysis) { category in
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
                    title: viewModel.salesInsights.hotProductTitle,
                    description: viewModel.salesInsights.hotProductDescription
                )
                
                InsightCard(
                    icon: "percent",
                    iconColor: .green,
                    title: viewModel.salesInsights.discountTitle,
                    description: viewModel.salesInsights.discountDescription
                )
                
                InsightCard(
                    icon: "lightbulb.fill",
                    iconColor: .orange,
                    title: viewModel.salesInsights.suggestionTitle,
                    description: viewModel.salesInsights.suggestionDescription
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
