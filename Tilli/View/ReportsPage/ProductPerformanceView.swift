//
//  ProductPerformanceView.swift
//  Tilli
//
//  Created by Peiyun on 2025/9/8.
//

import SwiftUI
import Charts

struct ProductPerformanceView: View {
    @ObservedObject var productPerformanceViewModel: ProductPerformanceViewModel
    @Binding var event: EventModel
    let timeRange: ReportTimeRange
    @State private var expandedProducts: Set<Int> = []

    init(viewModel: ProductPerformanceViewModel, event: Binding<EventModel>, timeRange: ReportTimeRange) {
        self.productPerformanceViewModel = viewModel
        self._event = event
        self.timeRange = timeRange
    }

    var body: some View {
        Group {
            if productPerformanceViewModel.topProducts.isEmpty && productPerformanceViewModel.categoryAnalysis.isEmpty {
                ScrollView {
                    LazyVStack(spacing: DesignSystem.Spacing.sm) {
                        EmptyStateView(
                            systemImage: "chart.bar.fill",
                            title: String.localized("performanceEmptyTitle"),
                            message: String.localized("performanceEmptyMessage")
                        )
                    }
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: DesignSystem.Spacing.sm) {
                        VStack(spacing: DesignSystem.Spacing.lg) {
                            // TOP 5 商品榜單
                            topProductsView
                            // 類別銷售彙總
                            categoryAnalysisView
                            // 銷售洞察
                            salesInsightsView
                        }
                    }
                    .padding(DesignSystem.Spacing.md)
                }
            }
        }
        .refreshable {
            productPerformanceViewModel.loadData(timeRange: timeRange)
        }
        .background(DesignSystem.ColorToken.paper)
    }

    // MARK: - Top Products View
    private var topProductsView: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
            // 熱門商品榜單 Header
            HStack {
                // 熱門商品榜單
                Text("performanceTopProducts")
                    .font(DesignSystem.Typography.title2)
                Spacer()
            }

            VStack(spacing: DesignSystem.Spacing.md) {
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
                        currency: event.currency,
                        isExpanded: expandedProducts.contains(product.rank)
                    ) {
                        toggleExpansion(for: product.rank)
                    }
                }
            }
        }
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.ColorToken.cardSurface)
        .cornerRadius(DesignSystem.Radius.md)
    }

    // MARK: - Category Analysis View
    private var categoryAnalysisView: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            // 類別銷售彙總
            Text("performanceCategoryAnalysis")
                .font(DesignSystem.Typography.title2)

            VStack(spacing: DesignSystem.Spacing.md) {
                // Pie Chart
                PieChartView(categories: productPerformanceViewModel.categoryAnalysis, currency: event.currency)
                    .frame(height: 250)

                // Category Details
                VStack(spacing: DesignSystem.Spacing.xs) {
                    ForEach(productPerformanceViewModel.categoryAnalysis) { category in
                        CategoryCard(
                            color: category.color,
                            name: category.name,
                            amount: category.amount,
                            percentage: category.percentage,
                            currency: event.currency
                        )
                    }
                }
            }
        }
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.ColorToken.cardSurface)
        .cornerRadius(DesignSystem.Radius.md)
    }

    // MARK: - Sales Insights View
    private var salesInsightsView: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            // 銷售洞察
            Text("performanceSalesInsights")
                .font(DesignSystem.Typography.title2)

            VStack(spacing: DesignSystem.Spacing.sm) {
                InsightCard(
                    icon: "chart.line.uptrend.xyaxis",
                    iconColor: DesignSystem.ColorToken.ink,
                    title: productPerformanceViewModel.salesInsights.hotProductTitle,
                    description: productPerformanceViewModel.salesInsights.hotProductDescription
                )

                // 只在有折扣資料時顯示
                if let discountTitle = productPerformanceViewModel.salesInsights.discountTitle,
                   let discountDescription = productPerformanceViewModel.salesInsights.discountDescription {
                    InsightCard(
                        icon: "percent",
                        iconColor: DesignSystem.ColorToken.ink,
                        title: discountTitle,
                        description: discountDescription
                    )
                }

                InsightCard(
                    icon: "lightbulb.fill",
                    iconColor: DesignSystem.ColorToken.ink,
                    title: productPerformanceViewModel.salesInsights.suggestionTitle,
                    description: productPerformanceViewModel.salesInsights.suggestionDescription
                )
            }
        }
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.ColorToken.cardSurface)
        .cornerRadius(DesignSystem.Radius.md)
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
