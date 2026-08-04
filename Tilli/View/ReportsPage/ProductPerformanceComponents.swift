//
//  ProductPerformanceComponents.swift
//  Tilli
//
//  Created by Peiyun on 2025/9/15.
//

import SwiftUI
import Charts

// MARK: - Product Ranking Card
struct ProductRankingCard: View {
    let rank: Int
    let name: String
    let category: String
    let salesCount: Int
    let revenue: Decimal
    let contributionRate: Int
    let unitPrice: Decimal?
    let originalPrice: Decimal?
    let discount: Decimal?
    let actualRevenue: Decimal?
    let currency: String
    let isExpanded: Bool
    let onToggle: () -> Void

    init(rank: Int, name: String, category: String, salesCount: Int, revenue: Decimal, contributionRate: Int, unitPrice: Decimal? = nil, originalPrice: Decimal? = nil, discount: Decimal? = nil, actualRevenue: Decimal? = nil, currency: String = "TWD", isExpanded: Bool = false, onToggle: @escaping () -> Void = {}) {
        self.rank = rank
        self.name = name
        self.category = category
        self.salesCount = salesCount
        self.revenue = revenue
        self.contributionRate = contributionRate
        self.unitPrice = unitPrice
        self.originalPrice = originalPrice
        self.discount = discount
        self.actualRevenue = actualRevenue
        self.currency = currency
        self.isExpanded = isExpanded
        self.onToggle = onToggle
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                // Rank Circle
                Circle()
                    .fill(DesignSystem.ColorToken.buttonFilled)
                    .frame(width: 32, height: 32)
                    .overlay(
                        Text("\(rank)")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(DesignSystem.ColorToken.onButtonFilled)
                    )

                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxs) {
                    Text(name)
                        .font(.system(size: 16, weight: .medium))
                    Text(category)
                        .font(.system(size: 13))
                        .foregroundColor(DesignSystem.ColorToken.muted)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: DesignSystem.Spacing.xxs) {
                    Text("\(contributionRate)%")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(DesignSystem.ColorToken.ink)
                    // 貢獻度
                    Text("performanceContribution")
                        .font(.system(size: 11))
                        .foregroundColor(DesignSystem.ColorToken.muted)
                }

                Button(action: onToggle) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(DesignSystem.ColorToken.muted)
                        .font(.system(size: 12))
                }
                .buttonStyle(PlainButtonStyle())
            }

            HStack {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxs) {
                    Text("\(salesCount)")
                        .font(.system(size: 20, weight: .bold))
                    // 銷售數量
                    Text("performanceSalesCount")
                        .font(.system(size: 11))
                        .foregroundColor(DesignSystem.ColorToken.muted)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: DesignSystem.Spacing.xxs) {
                    Text(MoneyHelper.format(revenue, currencyCode: currency))
                        .font(.system(size: 16, weight: .bold))
                    // 實際金額
                    Text("performanceActualAmount")
                        .font(.system(size: 11))
                        .foregroundColor(DesignSystem.ColorToken.muted)
                }
            }
            .padding(.top, DesignSystem.Spacing.xs)

            // Expanded Details
            if isExpanded {
                VStack(spacing: DesignSystem.Spacing.sm) {
                    Rectangle()
                        .fill(DesignSystem.ColorToken.muted.opacity(0.2))
                        .frame(height: 1)
                        .padding(.vertical, DesignSystem.Spacing.xs)

                    // 詳細資訊
                    Text("performanceDetailInfo")
                        .font(.system(size: 14, weight: .medium))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(spacing: DesignSystem.Spacing.xs) {
                        if let unitPrice = unitPrice {
                            HStack {
                                // 單價
                                Text("performanceUnitPrice")
                                    .foregroundColor(DesignSystem.ColorToken.muted)
                                Spacer()
                                Text(MoneyHelper.format(unitPrice, currencyCode: currency))
                                    .fontWeight(.medium)
                            }
                        }

                        if let originalPrice = originalPrice {
                            HStack {
                                // 原價總額
                                Text("performanceOriginalTotal")
                                    .foregroundColor(DesignSystem.ColorToken.muted)
                                Spacer()
                                Text(MoneyHelper.format(originalPrice, currencyCode: currency))
                                    .fontWeight(.medium)
                            }
                        }

                        if let discount = discount {
                            HStack {
                                // 折扣總額
                                Text("performanceDiscountTotal")
                                    .foregroundColor(DesignSystem.ColorToken.muted)
                                Spacer()
                                Text(MoneyHelper.format(discount, currencyCode: currency))
                                    .fontWeight(.medium)
                                    .foregroundColor(DesignSystem.ColorToken.alertRed)
                            }
                        }

                        if let actualRevenue = actualRevenue {
                            HStack {
                                // 實收金額
                                Text("performanceActualRevenue")
                                    .foregroundColor(DesignSystem.ColorToken.muted)
                                Spacer()
                                Text(MoneyHelper.format(actualRevenue, currencyCode: currency))
                                    .fontWeight(.bold)
                                    .foregroundColor(DesignSystem.ColorToken.ink)
                            }
                        }
                    }
                    .font(.system(size: 13))

                    // Progress Bar
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxs) {
                        HStack {
                            // 銷售表現
                            Text("performanceSalesPerformance")
                                .font(.system(size: 11))
                                .foregroundColor(DesignSystem.ColorToken.muted)
                            Spacer()
                            Text("\(contributionRate)%")
                                .font(.system(size: 11))
                                .foregroundColor(DesignSystem.ColorToken.muted)
                        }

                        ProgressView(value: max(0, min(Double(contributionRate), 100)), total: 100)
                            .progressViewStyle(LinearProgressViewStyle(tint: DesignSystem.ColorToken.ink))
                            .scaleEffect(x: 1, y: 2, anchor: .center)
                    }
                }
            }
        }
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.ColorToken.cardSurface)
        .cornerRadius(DesignSystem.Radius.md)
        .shadow(
            color: DesignSystem.Shadow.cardColor,
            radius: DesignSystem.Shadow.cardRadius,
            x: DesignSystem.Shadow.cardX,
            y: DesignSystem.Shadow.cardY
        )
        .onTapGesture {
            onToggle()
        }
    }
}

// MARK: - Pie Chart View
struct PieChartView: View {
    let categories: [CategoryAnalysisData]
    let currency: String

    var body: some View {
        ZStack {
            // Pie Chart using Charts framework (iOS 16+)
            if #available(iOS 16.0, *) {
                Chart(categories, id: \.name) { category in
                    SectorMark(
                        angle: .value("Amount", category.percentage),
                        innerRadius: .ratio(0.6),
                        outerRadius: .ratio(1.0)
                    )
                    .foregroundStyle(category.color)
                }
                .frame(height: 200)
            } else {
                // Fallback for older iOS versions
                Circle()
                    .fill(DesignSystem.ColorToken.muted.opacity(0.2))
                    .frame(height: 200)
                    .overlay(
                        // 圖表
                        Text("performanceChartFallback")
                            .font(DesignSystem.Typography.title2)
                            .foregroundColor(DesignSystem.ColorToken.muted)
                    )
            }

            // Center total amount
            VStack(spacing: DesignSystem.Spacing.xxs) {
                // 總銷售額
                Text("performanceTotalSales")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.ColorToken.muted)
                let totalAmount = categories.reduce(Decimal(0)) { MoneyHelper.add($0, $1.amount) }
                Text(MoneyHelper.format(totalAmount, currencyCode: currency))
                    .font(.title3)
                    .fontWeight(.bold)
            }
        }
    }
}

// MARK: - Category Card
struct CategoryCard: View {
    let color: Color
    let name: String
    let amount: Decimal
    let percentage: Int
    let currency: String

    var body: some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 12, height: 12)

            Text(name)
                .font(.system(size: 15))

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(MoneyHelper.format(amount, currencyCode: currency))
                    .font(.system(size: 15, weight: .medium))
                Text("\(percentage)%")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.ColorToken.muted)
            }
        }
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.ColorToken.cardSurface)
        .cornerRadius(DesignSystem.Radius.sm)
        .shadow(
            color: DesignSystem.Shadow.cardColor,
            radius: DesignSystem.Shadow.cardRadius,
            x: DesignSystem.Shadow.cardX,
            y: DesignSystem.Shadow.cardY
        )
    }
}

// MARK: - Insight Card
struct InsightCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
            Image(systemName: icon)
                .foregroundColor(iconColor)
                .font(.system(size: 18))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxs) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                Text(description)
                    .font(.system(size: 13))
                    .foregroundColor(DesignSystem.ColorToken.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.ColorToken.quietFill)
        .cornerRadius(DesignSystem.Radius.sm)
    }
}

// MARK: - Extensions
extension String {
    var addingThousandsSeparator: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","

        if let number = Int(self) {
            return formatter.string(from: NSNumber(value: number)) ?? self
        }
        return self
    }
}
