//
//  WorkspaceView.swift
//  Tilli
//
//  Created by Peiyun on 2026/7/30.
//

import SwiftUI

struct WorkspaceView: View {

    let event: EventModel
    @EnvironmentObject var transactionDataManager: TransactionRepository

    private var allTransactions: [TransactionModel] {
        transactionDataManager.fetchTransactions(forEventId: event.id)
    }

    private var totalRevenue: Decimal {
        allTransactions.reduce(Decimal.zero) { $0 + $1.totalAmount }
    }

    private var totalOrderCount: Int {
        allTransactions.count
    }

    var body: some View {
        ScrollView {
            VStack(spacing: DesignSystem.Spacing.lg) {
                headerSection
                statsSection
                buttonsSection
            }
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.top, DesignSystem.Spacing.md)
            .padding(.bottom, DesignSystem.Spacing.lg)
        }
        .background(DesignSystem.ColorToken.paper)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                // 場次名稱
                Text(event.title)
                    .font(DesignSystem.Typography.title1)
                    .foregroundColor(DesignSystem.ColorToken.ink)

                Spacer(minLength: DesignSystem.Spacing.xs)

                statusPill
            }

            // 日期範圍
            Text(event.displayTimeInfo)
                .font(DesignSystem.Typography.body)
                .foregroundColor(DesignSystem.ColorToken.muted)
        }
    }

    @ViewBuilder
    private var statusPill: some View {
        if event.status == .ongoing {
            Text("eventStatusOngoing")
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.ColorToken.marketGreen)
                .padding(.horizontal, DesignSystem.Spacing.xs)
                .padding(.vertical, 4)
                .background(DesignSystem.ColorToken.marketGreenLight)
                .clipShape(Capsule())
        } else {
            Text(event.status.localizedDescription)
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.ColorToken.muted)
                .padding(.horizontal, DesignSystem.Spacing.xs)
                .padding(.vertical, 4)
                .background(DesignSystem.ColorToken.quietFill)
                .clipShape(Capsule())
        }
    }

    // MARK: - Stats

    private var statsSection: some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            revenueCard
            orderCountCard
        }
    }

    private var revenueCard: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            // 總營收
            Text("workspaceTotalRevenue")
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.ColorToken.muted)

            Text(MoneyHelper.format(totalRevenue, currencyCode: event.currency))
                .font(DesignSystem.Typography.display)
                .foregroundColor(DesignSystem.ColorToken.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.ColorToken.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .stroke(DesignSystem.Border.cardColor, lineWidth: DesignSystem.Border.cardWidth)
        )
        .shadow(
            color: DesignSystem.Shadow.cardColor,
            radius: DesignSystem.Shadow.cardRadius,
            x: DesignSystem.Shadow.cardX,
            y: DesignSystem.Shadow.cardY
        )
    }

    private var orderCountCard: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            // 訂單數
            Text("workspaceTotalOrders")
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.ColorToken.muted)

            Text("\(totalOrderCount)")
                .font(DesignSystem.Typography.display)
                .foregroundColor(DesignSystem.ColorToken.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.ColorToken.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .stroke(DesignSystem.Border.cardColor, lineWidth: DesignSystem.Border.cardWidth)
        )
        .shadow(
            color: DesignSystem.Shadow.cardColor,
            radius: DesignSystem.Shadow.cardRadius,
            x: DesignSystem.Shadow.cardX,
            y: DesignSystem.Shadow.cardY
        )
    }

    // MARK: - Buttons

    private var buttonsSection: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            workspaceButton(
                icon: "dollarsign.circle",
                // 開始收銀
                titleKey: "workspacePosButton",
                destination: POSView(event: event)
            )

            workspaceButton(
                icon: "shippingbox",
                // 管理商品
                titleKey: "workspaceInventoryButton",
                destination: InventoryView(event: event)
            )

            workspaceButton(
                icon: "chart.bar",
                // 查看分析
                titleKey: "workspaceReportsButton",
                destination: reportsPlaceholder
            )
        }
    }

    private func workspaceButton<Destination: View>(
        icon: String,
        titleKey: LocalizedStringKey,
        destination: Destination
    ) -> some View {
        NavigationLink {
            destination
        } label: {
            VStack(spacing: DesignSystem.Spacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundColor(DesignSystem.ColorToken.ink)

                // 按鈕標題
                Text(titleKey)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(DesignSystem.ColorToken.ink)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DesignSystem.Spacing.md)
            .background(DesignSystem.ColorToken.cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                    .stroke(DesignSystem.Border.cardColor, lineWidth: DesignSystem.Border.cardWidth)
            )
            .shadow(
                color: DesignSystem.Shadow.cardColor,
                radius: DesignSystem.Shadow.cardRadius,
                x: DesignSystem.Shadow.cardX,
                y: DesignSystem.Shadow.cardY
            )
        }
    }

    // MARK: - Placeholder Destinations

    private var reportsPlaceholder: some View {
        Text("Reports - TODO")
            .font(DesignSystem.Typography.title1)
            .foregroundColor(DesignSystem.ColorToken.muted)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DesignSystem.ColorToken.paper)
            .navigationTitle("workspaceReportsButton")
    }
}
