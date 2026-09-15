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
    let event: EventModel
    let timeRange: ReportTimeRange
    @State private var expandedProducts: Set<Int> = []
    @State private var showUnsoldProducts = false

    init(viewModel: ProductPerformanceViewModel, event: EventModel, timeRange: ReportTimeRange) {
        self.productPerformanceViewModel = viewModel
        self.event = event
        self.timeRange = timeRange
    }

    var body: some View {
        Group {
            if !productPerformanceViewModel.hasSalesInRange {
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
                            // 商品銷售排行（只列有賣出的）
                            topProductsView
                            // 本期未售出（預設收合）
                            if !productPerformanceViewModel.unsoldProducts.isEmpty {
                                unsoldProductsView
                            }
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
                        averageUnitPrice: product.averageUnitPrice,
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

    // MARK: - 本期未售出

    /// 摺疊區：只回答「哪些沒賣掉」。
    ///
    /// 不給名次與營收欄位 —— 對這些商品一律是 0／沒有意義，
    /// 放進主排行榜只會讓收攤時要看的那張表變長變難讀（見 FEATURE_PLAN_V1.md §5.1）。
    private var unsoldProductsView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showUnsoldProducts.toggle()
                }
            } label: {
                HStack {
                    // 本期未售出（N 項）
                    Text("performanceUnsoldSection \(productPerformanceViewModel.unsoldProducts.count)")
                        .font(DesignSystem.Typography.title2)
                        .foregroundColor(DesignSystem.ColorToken.ink)
                    Spacer()
                    Image(systemName: showUnsoldProducts ? "chevron.up" : "chevron.down")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.ColorToken.muted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showUnsoldProducts {
                VStack(spacing: 0) {
                    ForEach(productPerformanceViewModel.unsoldProducts) { product in
                        HStack(spacing: DesignSystem.Spacing.xs) {
                            Text(product.name)
                                .foregroundColor(DesignSystem.ColorToken.ink)

                            if product.isDisabled {
                                // 已下架
                                Text("performanceUnsoldDisabledTag")
                                    .font(DesignSystem.Typography.caption)
                                    .padding(.horizontal, DesignSystem.Spacing.xxs)
                                    .padding(.vertical, 2)
                                    .background(DesignSystem.ColorToken.quietFill)
                                    .foregroundColor(DesignSystem.ColorToken.muted)
                                    .cornerRadius(DesignSystem.Radius.sm)
                            }

                            Spacer()

                            Text(product.category)
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.ColorToken.muted)
                        }
                        .padding(.vertical, DesignSystem.Spacing.xs)
                    }
                }
                .padding(.top, DesignSystem.Spacing.sm)
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
