//
//  SalesAnalyticsView.swift
//  Tilli
//
//  Created by Peiyun on 2025/9/16.
//

import SwiftUI
import Charts

struct SalesAnalyticsView: View {
    @ObservedObject var salesAnalyticsViewModel: SalesAnalyticsViewModel
    @Binding var event: EventModel
    let timeRange: ReportTimeRange

    // 時間分佈圖選中狀態
    @State private var selectedHourData: HourlyAnalysisData?

    // 營收趨勢選中狀態
    @State private var selectedDailyData: DailyRevenueData?
    @State private var selectedMonthlyData: MonthlyRevenueData?

    init(viewModel: SalesAnalyticsViewModel, event: Binding<EventModel>, timeRange: ReportTimeRange) {
        self.salesAnalyticsViewModel = viewModel
        self._event = event
        self.timeRange = timeRange
    }

    var body: some View {
        Group {
            if salesAnalyticsViewModel.salesOverview?.totalTransactions == 0 || salesAnalyticsViewModel.salesOverview == nil {
                ScrollView {
                    LazyVStack(spacing: DesignSystem.Spacing.sm) {
                        EmptyStateView(
                            systemImage: "chart.line.uptrend.xyaxis",
                            // 尚無銷售分析
                            title: String(localized: "analyticsEmptyTitle"),
                            // 完成結帳後，銷售分析會顯示在這裡
                            message: String(localized: "analyticsEmptyMessage")
                        )
                    }
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: DesignSystem.Spacing.sm) {
                        VStack(spacing: DesignSystem.Spacing.lg) {
                            // 總銷售額區塊
                            salesSummaryView
                            // 支付方式分布
                            paymentMethodDistribution
                            // 時間分布圖與詳細記錄（合併為一個卡片）
                            timeDistributionWithDetailView
                            // 營收趨勢（條件顯示：非單日且天數 > 1）
                            if shouldShowRevenueTrend {
                                revenueTrendView
                            }
                        }
                    }
                    .padding(DesignSystem.Spacing.md)
                }
            }
        }
        .refreshable {
            salesAnalyticsViewModel.loadData(timeRange: timeRange)
        }
        .background(DesignSystem.ColorToken.paper)
        .onChange(of: timeRange) {
            selectedHourData = nil
            selectedDailyData = nil
            selectedMonthlyData = nil
        }
    }

    // MARK: - 總銷售額視圖
    private var salesSummaryView: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            salesCard
            transactionsCard
        }
    }

    // 銷售額卡片
    private var salesCard: some View {
        VStack {
            // 總銷售額
            Text("analyticsTotalSales")
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.ColorToken.muted)
            if let totalAmount = salesAnalyticsViewModel.salesOverview?.totalAmount {
                Text(MoneyHelper.format(totalAmount, currencyCode: event.currency))
                    .font(DesignSystem.Typography.title2)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            } else {
                Text(MoneyHelper.format(0, currencyCode: event.currency))
                    .font(DesignSystem.Typography.title2)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 60)
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.ColorToken.cardSurface)
        .cornerRadius(DesignSystem.Radius.md)
    }

    // 交易筆數卡片
    private var transactionsCard: some View {
        VStack {
            // 交易筆數
            Text("analyticsTotalTransactions")
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.ColorToken.muted)
            Text("\(salesAnalyticsViewModel.salesOverview?.totalTransactions ?? 0)")
                .font(DesignSystem.Typography.title2)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 60)
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.ColorToken.cardSurface)
        .cornerRadius(DesignSystem.Radius.md)
    }

    // MARK: - 支付方式分布
    private var paymentMethodDistribution: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            // 支付方式分布
            Text("analyticsPaymentDistribution")
                .font(.headline)
                .padding(.horizontal, DesignSystem.Spacing.md)
                .padding(.vertical, DesignSystem.Spacing.md)

            // 圓餅圖 - 置中
            HStack {
                Spacer()
                VStack {
                    if #available(iOS 16.0, *) {
                        pieChartView
                    } else {
                        legacyPieChart
                    }
                }
                Spacer()
            }
            .padding(.vertical, DesignSystem.Spacing.lg)

            // 支付方式詳情
            VStack(spacing: 0) {
                HStack {
                    // 支付方式
                    Text("analyticsPaymentMethodHeader")
                        .font(DesignSystem.Typography.caption)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // 交易金額
                    Text("analyticsTransactionAmountHeader")
                        .font(DesignSystem.Typography.caption)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity, alignment: .center)

                    // 交易數
                    Text("analyticsTransactionCountHeader")
                        .font(DesignSystem.Typography.caption)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity, alignment: .center)

                    // 占比
                    Text("analyticsPercentageHeader")
                        .font(DesignSystem.Typography.caption)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding(.vertical, DesignSystem.Spacing.xs)
                .padding(.horizontal, DesignSystem.Spacing.lg)
                .background(DesignSystem.ColorToken.paper)

                ForEach(salesAnalyticsViewModel.paymentMethodData) { method in
                    HStack {
                        HStack {
                            Circle()
                                .fill(method.color)
                                .frame(width: 12, height: 12)
                            Text(method.name)
                                .font(.system(size: 14))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Text(MoneyHelper.format(method.amount, currencyCode: event.currency))
                            .font(.system(size: 14, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .center)

                        Text("\(method.transactions)")
                            .font(.system(size: 14))
                            .frame(maxWidth: .infinity, alignment: .center)

                        Text("\(method.percentage)%")
                            .font(.system(size: 14))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .padding(.vertical, DesignSystem.Spacing.xs)
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    .background(DesignSystem.ColorToken.cardSurface)

                    if method.id != salesAnalyticsViewModel.paymentMethodData.last?.id {
                        Divider()
                            .padding(.horizontal, DesignSystem.Spacing.lg)
                    }
                }
            }
        }
        .background(DesignSystem.ColorToken.cardSurface)
        .cornerRadius(DesignSystem.Radius.md)
    }

    // MARK: - Pie Chart View (iOS 16+)
    @available(iOS 16.0, *)
    private var pieChartView: some View {
        Chart {
            ForEach(salesAnalyticsViewModel.paymentMethodData) { method in
                SectorMark(
                    angle: .value("交易數", method.transactions),
                    innerRadius: .ratio(0.5),
                    angularInset: 2
                )
                .foregroundStyle(method.color)
                .opacity(0.8)
            }
        }
        .frame(width: 150, height: 150)
    }

    // MARK: - Legacy Pie Chart (iOS 15 and below)
    private var legacyPieChart: some View {
        let cashData = salesAnalyticsViewModel.paymentMethodData.first { $0.method == .cash }
        let ratio = Double(cashData?.transactions ?? 0) / Double(salesAnalyticsViewModel.salesOverview?.totalTransactions ?? 1)

        return ZStack {
            Circle()
                .trim(from: 0, to: ratio)
                .stroke(DesignSystem.ChartColor.secondaryGradient, lineWidth: 40)
                .rotationEffect(.degrees(-90))

            Circle()
                .trim(from: ratio, to: 1.0)
                .stroke(DesignSystem.ChartColor.secondary, lineWidth: 40)
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 150, height: 150)
    }

    // MARK: - 時間分布圖與詳細記錄
    private var timeDistributionWithDetailView: some View {
        let content = VStack(alignment: .leading, spacing: 0) {
            // 圖表部分
            VStack(alignment: .leading) {
                // 時間分布圖
                Text("analyticsTimeDistribution")
                    .font(.headline)
                    .padding(.horizontal, DesignSystem.Spacing.md)
                    .padding(.vertical, DesignSystem.Spacing.md)

                if #available(iOS 16.0, *) {
                    barChartView
                } else {
                    // iOS 16 以下的替代方案
                    customBarChart
                }

                // 圖表說明
                HStack {
                    VStack(alignment: .leading) {
                        // 最高銷售額
                        Text("analyticsPeakSales")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.ColorToken.muted)
                        if let peakAmount = salesAnalyticsViewModel.salesOverview?.peakHourAmount {
                            Text(MoneyHelper.format(peakAmount, currencyCode: event.currency))
                                .font(.caption2)
                                .foregroundColor(DesignSystem.ColorToken.muted)
                        } else {
                            Text(MoneyHelper.format(0, currencyCode: event.currency))
                                .font(.caption2)
                                .foregroundColor(DesignSystem.ColorToken.muted)
                        }
                    }

                    Spacer()

                    VStack(alignment: .trailing) {
                        // 總交易數
                        Text("analyticsTotalCount")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.ColorToken.muted)
                        Text("\(salesAnalyticsViewModel.salesOverview?.totalTransactions ?? 0)")
                            .font(.caption2)
                            .foregroundColor(DesignSystem.ColorToken.muted)
                    }
                }
                .padding(.horizontal, DesignSystem.Spacing.md)
                .padding(.bottom, DesignSystem.Spacing.md)
            }

            // 詳細記錄表格
            VStack(spacing: 0) {
                // 表頭
                HStack {
                    // 時段
                    Text("analyticsTimePeriodHeader")
                        .font(DesignSystem.Typography.caption)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // 銷售額
                    Text("analyticsSalesAmountHeader")
                        .font(DesignSystem.Typography.caption)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity, alignment: .center)

                    // 交易數
                    Text("analyticsTransactionCountHeader")
                        .font(DesignSystem.Typography.caption)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity, alignment: .center)

                    // 平均客單價
                    Text("analyticsAvgOrderValue")
                        .font(DesignSystem.Typography.caption)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding(.vertical, DesignSystem.Spacing.xs)
                .padding(.horizontal, DesignSystem.Spacing.lg)
                .background(DesignSystem.ColorToken.paper)

                // 可滾動的數據列表
                ScrollViewReader { scrollProxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(salesAnalyticsViewModel.hourlyData) { data in
                                HStack {
                                    Text(data.hourString)
                                        .font(.system(size: 14, design: .monospaced))
                                        .frame(maxWidth: .infinity, alignment: .leading)

                                    Text(MoneyHelper.format(data.amount, currencyCode: event.currency))
                                        .font(.system(size: 14, design: .monospaced))
                                        .frame(maxWidth: .infinity, alignment: .center)

                                    Text("\(data.transactions)")
                                        .font(.system(size: 14))
                                        .frame(maxWidth: .infinity, alignment: .center)

                                    Text(MoneyHelper.format(data.avgPrice, currencyCode: event.currency))
                                        .font(.system(size: 14, design: .monospaced))
                                        .frame(maxWidth: .infinity, alignment: .trailing)
                                }
                                .padding(.vertical, DesignSystem.Spacing.xs)
                                .padding(.horizontal, DesignSystem.Spacing.lg)
                                .background(selectedHourData?.hour == data.hour ? DesignSystem.ColorToken.ink.opacity(0.1) : DesignSystem.ColorToken.cardSurface)
                                .id(data.hourString)
                                .onTapGesture {
                                    selectedHourData = data
                                }

                                if data.hour != salesAnalyticsViewModel.hourlyData.last?.hour {
                                    Divider()
                                        .padding(.horizontal, DesignSystem.Spacing.lg)
                                }
                            }
                        }
                        // 強制刷新：當數據變化時重建列表
                        .id("\(timeRange.displayText)-\(salesAnalyticsViewModel.salesOverview?.totalAmount ?? 0)")
                    }
                    .frame(height: 200)
                    .onChange(of: selectedHourData?.hour) { _, newHour in
                        if let hour = newHour {
                            let hourString = String(format: "%02d:00", hour)
                            withAnimation(.easeInOut(duration: 0.3)) {
                                scrollProxy.scrollTo(hourString, anchor: .center)
                            }
                        }
                    }
                }
            }
        }
        .background(DesignSystem.ColorToken.cardSurface)
        .cornerRadius(DesignSystem.Radius.md)

        return content
    }

    // MARK: - Bar Chart View (iOS 16+)
    @available(iOS 16.0, *)
    private var barChartView: some View {
        Chart {
            ForEach(salesAnalyticsViewModel.hourlyData) { data in
                BarMark(
                    x: .value("時間", data.hourString),
                    y: .value("金額", MoneyHelper.toUIDouble(data.amount))
                )
                .foregroundStyle(
                    selectedHourData?.hour == data.hour
                        ? DesignSystem.ChartColor.primary
                        : (selectedHourData == nil ? DesignSystem.ChartColor.primary : DesignSystem.ChartColor.primary.opacity(0.3))
                )
            }

            // 選中時顯示標記線
            if let selected = selectedHourData {
                RuleMark(x: .value("選中", selected.hourString))
                    .foregroundStyle(DesignSystem.ColorToken.muted.opacity(0.3))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
            }
        }
        .chartXAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let hourString = value.as(String.self) {
                        let hour = Int(hourString.prefix(2)) ?? 0
                        if hour % 4 == 0 {
                            Text(hourString)
                        }
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading)
        }
        .frame(height: 200)
        .padding(.horizontal, DesignSystem.Spacing.md)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        let plotFrame = geometry[proxy.plotFrame!]
                        let tapX = location.x - plotFrame.origin.x

                        // 找到最接近點擊位置的柱子
                        var closestData: HourlyAnalysisData?
                        var closestDistance: CGFloat = .infinity

                        for data in salesAnalyticsViewModel.hourlyData {
                            if let barX = proxy.position(forX: data.hourString) {
                                let distance = abs(barX - tapX)
                                if distance < closestDistance {
                                    closestDistance = distance
                                    closestData = data
                                }
                            }
                        }

                        if let matched = closestData {
                            selectedHourData = matched
                        }
                    }
            }
        }
    }

    // MARK: - 自定義柱狀圖（適用於 iOS 16 以下）
    private var customBarChart: some View {
        let maxAmount = salesAnalyticsViewModel.hourlyData.max { $0.amount < $1.amount }?.amount ?? Decimal(1)

        return HStack(alignment: .bottom, spacing: 2) {
            ForEach(salesAnalyticsViewModel.hourlyData) { data in
                let isSelected = selectedHourData?.hour == data.hour
                let opacity: Double = selectedHourData == nil ? 1.0 : (isSelected ? 1.0 : 0.3)

                Rectangle()
                    .fill(LinearGradient(
                        colors: [DesignSystem.ChartColor.primary.opacity(opacity), DesignSystem.ChartColor.primaryGradient.opacity(opacity)],
                        startPoint: .bottom,
                        endPoint: .top
                    ))
                    .frame(
                        width: 8,
                        height: maxAmount > 0
                            ? CGFloat(MoneyHelper.toUIDouble(data.amount)) / CGFloat(MoneyHelper.toUIDouble(maxAmount)) * 150
                            : 0
                    )
                    .onTapGesture {
                        selectedHourData = data
                    }
            }
        }
        .frame(height: 200)
        .padding(.horizontal, DesignSystem.Spacing.md)
    }

    // MARK: - Revenue Trend

    /// 是否顯示營收趨勢（單日不顯示，天數 > 1 才顯示）
    private var shouldShowRevenueTrend: Bool {
        event.dateType != .single && timeRange.dayCount > 1
    }

    /// 營收趨勢視圖
    private var revenueTrendView: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            HStack {
                // 營收趨勢
                Text("analyticsRevenueTrend")
                    .font(.headline)

                Spacer()

                // 超過 90 天顯示切換按鈕
                if timeRange.dayCount > 90 {
                    // 視圖
                    Picker("analyticsViewLabel", selection: $salesAnalyticsViewModel.trendViewMode) {
                        // 每日
                        Text("analyticsDailyView").tag(SalesAnalyticsViewModel.TrendViewMode.daily)
                        // 每月
                        Text("analyticsMonthlyView").tag(SalesAnalyticsViewModel.TrendViewMode.monthly)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 120)
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.top, DesignSystem.Spacing.md)

            // 圖表區域
            if timeRange.dayCount > 90 && salesAnalyticsViewModel.trendViewMode == .monthly {
                // 每月視圖
                monthlyRevenueChart
                monthlyRevenueDetailList
            } else {
                // 每日視圖
                dailyRevenueChart
                revenueTrendDetailList
            }
        }
        .background(DesignSystem.ColorToken.cardSurface)
        .cornerRadius(DesignSystem.Radius.md)
    }

    /// 每日營收圖表
    private var dailyRevenueChart: some View {
        Group {
            if timeRange.dayCount <= 7 {
                // ≤7天：柱狀圖
                dailyBarChart
            } else {
                // >7天：折線圖
                dailyLineChart
            }
        }
    }

    /// 每日柱狀圖
    private var dailyBarChart: some View {
        let maxAmount = salesAnalyticsViewModel.maxDailyAmount

        return VStack(spacing: DesignSystem.Spacing.xs) {
            HStack(alignment: .bottom, spacing: DesignSystem.Spacing.xxs) {
                ForEach(salesAnalyticsViewModel.dailyRevenue) { data in
                    let isSelected = selectedDailyData?.date == data.date
                    let opacity: Double = selectedDailyData == nil ? 1.0 : (isSelected ? 1.0 : 0.3)

                    VStack(spacing: DesignSystem.Spacing.xxs) {
                        // 金額標籤（≤7天時顯示）
                        if timeRange.dayCount <= 7 {
                            Text(MoneyHelper.format(data.amount, currencyCode: event.currency))
                                .font(.system(size: 9))
                                .foregroundColor(DesignSystem.ColorToken.muted)
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                        }

                        // 柱狀
                        RoundedRectangle(cornerRadius: 4)
                            .fill(LinearGradient(
                                colors: [DesignSystem.ChartColor.primary.opacity(opacity), DesignSystem.ChartColor.primaryGradient.opacity(opacity)],
                                startPoint: .bottom,
                                endPoint: .top
                            ))
                            .frame(
                                height: maxAmount > 0
                                    ? CGFloat(MoneyHelper.toUIDouble(data.amount)) / CGFloat(MoneyHelper.toUIDouble(maxAmount)) * 120
                                    : 0
                            )
                            .frame(minHeight: data.amount > 0 ? 4 : 0)

                        // 日期標籤
                        Text(data.dateString)
                            .font(.system(size: 9))
                            .foregroundColor(DesignSystem.ColorToken.muted)
                    }
                    .frame(maxWidth: .infinity)
                    .onTapGesture {
                        selectedDailyData = data
                    }
                }
            }
            .frame(height: timeRange.dayCount <= 7 ? 180 : 150)
            .padding(.horizontal, DesignSystem.Spacing.md)
        }
    }

    /// 每日折線圖 (iOS 16+)
    @available(iOS 16.0, *)
    private var dailyLineChart: some View {
        Chart {
            ForEach(salesAnalyticsViewModel.dailyRevenue) { data in
                LineMark(
                    x: .value("日期", data.date),
                    y: .value("金額", MoneyHelper.toUIDouble(data.amount))
                )
                .foregroundStyle(DesignSystem.ChartColor.primary)

                AreaMark(
                    x: .value("日期", data.date),
                    y: .value("金額", MoneyHelper.toUIDouble(data.amount))
                )
                .foregroundStyle(DesignSystem.ChartColor.primary.opacity(0.1))
            }

            // 選中時顯示圓點標記
            if let selected = selectedDailyData {
                PointMark(
                    x: .value("日期", selected.date),
                    y: .value("金額", MoneyHelper.toUIDouble(selected.amount))
                )
                .foregroundStyle(DesignSystem.ChartColor.primary)
                .symbolSize(100)

                // 垂直標記線
                RuleMark(x: .value("選中", selected.date))
                    .foregroundStyle(DesignSystem.ColorToken.muted.opacity(0.3))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: max(1, timeRange.dayCount / 7))) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month().day())
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading)
        }
        .frame(height: 200)
        .padding(.horizontal, DesignSystem.Spacing.md)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        let plotFrame = geometry[proxy.plotFrame!]
                        let tapX = location.x - plotFrame.origin.x

                        // 找到最接近點擊位置的數據點
                        var closestData: DailyRevenueData?
                        var closestDistance: CGFloat = .infinity

                        for data in salesAnalyticsViewModel.dailyRevenue {
                            if let dataX = proxy.position(forX: data.date) {
                                let distance = abs(dataX - tapX)
                                if distance < closestDistance {
                                    closestDistance = distance
                                    closestData = data
                                }
                            }
                        }

                        if let matched = closestData {
                            selectedDailyData = matched
                        }
                    }
            }
        }
    }

    /// 每月營收圖表
    private var monthlyRevenueChart: some View {
        let maxAmount = salesAnalyticsViewModel.maxMonthlyAmount

        return VStack(spacing: DesignSystem.Spacing.xs) {
            ForEach(salesAnalyticsViewModel.monthlyRevenue) { data in
                let isSelected = selectedMonthlyData?.year == data.year && selectedMonthlyData?.month == data.month
                let opacity: Double = selectedMonthlyData == nil ? 1.0 : (isSelected ? 1.0 : 0.3)

                HStack {
                    Text(data.fullMonthString)
                        .font(.system(size: 12))
                        .frame(width: 60, alignment: .leading)

                    GeometryReader { geometry in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(LinearGradient(
                                colors: [DesignSystem.ChartColor.secondary.opacity(opacity), DesignSystem.ChartColor.secondaryGradient.opacity(opacity)],
                                startPoint: .leading,
                                endPoint: .trailing
                            ))
                            .frame(
                                width: maxAmount > 0
                                    ? geometry.size.width * CGFloat(MoneyHelper.toUIDouble(data.amount)) / CGFloat(MoneyHelper.toUIDouble(maxAmount))
                                    : 0
                            )
                    }
                    .frame(height: 24)

                    Text(MoneyHelper.format(data.amount, currencyCode: event.currency))
                        .font(.system(size: 12, design: .monospaced))
                        .frame(width: 80, alignment: .trailing)
                }
                .onTapGesture {
                    selectedMonthlyData = data
                }
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.md)
        .padding(.bottom, DesignSystem.Spacing.md)
    }

    /// 營收趨勢明細列表
    private var revenueTrendDetailList: some View {
        VStack(spacing: 0) {
            // 表頭
            HStack {
                // 日期
                Text("analyticsDateHeader")
                    .font(DesignSystem.Typography.caption)
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // 交易數
                Text("analyticsTransactionCountHeader")
                    .font(DesignSystem.Typography.caption)
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity, alignment: .center)

                // 營收
                Text("analyticsRevenueHeader")
                    .font(DesignSystem.Typography.caption)
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.vertical, DesignSystem.Spacing.xs)
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .background(DesignSystem.ColorToken.paper)

            // 數據列表
            ScrollViewReader { scrollProxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(salesAnalyticsViewModel.dailyRevenue) { data in
                            HStack {
                                Text(data.fullDateString)
                                    .font(.system(size: 14))
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                Text("\(data.count)")
                                    .font(.system(size: 14))
                                    .frame(maxWidth: .infinity, alignment: .center)

                                Text(MoneyHelper.format(data.amount, currencyCode: event.currency))
                                    .font(.system(size: 14, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                            }
                            .padding(.vertical, DesignSystem.Spacing.xs)
                            .padding(.horizontal, DesignSystem.Spacing.lg)
                            .background(selectedDailyData?.date == data.date ? DesignSystem.ColorToken.ink.opacity(0.1) : DesignSystem.ColorToken.cardSurface)
                            .id(data.fullDateString)
                            .onTapGesture {
                                selectedDailyData = data
                            }

                            if data.id != salesAnalyticsViewModel.dailyRevenue.last?.id {
                                Divider()
                                    .padding(.horizontal, DesignSystem.Spacing.lg)
                            }
                        }
                    }
                    // 強制刷新
                    .id("\(timeRange.displayText)-\(salesAnalyticsViewModel.salesOverview?.totalAmount ?? 0)-daily")
                }
                .frame(height: min(CGFloat(salesAnalyticsViewModel.dailyRevenue.count) * 40, 233))
                .onChange(of: selectedDailyData?.date) {
                    if let dateString = selectedDailyData?.fullDateString {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            scrollProxy.scrollTo(dateString, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    /// 月度營收明細列表
    private var monthlyRevenueDetailList: some View {
        VStack(spacing: 0) {
            // 表頭
            HStack {
                // 月份
                Text("analyticsMonthHeader")
                    .font(DesignSystem.Typography.caption)
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // 交易數
                Text("analyticsTransactionCountHeader")
                    .font(DesignSystem.Typography.caption)
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity, alignment: .center)

                // 營收
                Text("analyticsRevenueHeader")
                    .font(DesignSystem.Typography.caption)
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.vertical, DesignSystem.Spacing.xs)
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .background(DesignSystem.ColorToken.paper)

            // 數據列表
            ScrollViewReader { scrollProxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(salesAnalyticsViewModel.monthlyRevenue) { data in
                            let isSelected = selectedMonthlyData?.year == data.year && selectedMonthlyData?.month == data.month

                            HStack {
                                Text(data.fullMonthString)
                                    .font(.system(size: 14))
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                Text("\(data.count)")
                                    .font(.system(size: 14))
                                    .frame(maxWidth: .infinity, alignment: .center)

                                Text(MoneyHelper.format(data.amount, currencyCode: event.currency))
                                    .font(.system(size: 14, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                            }
                            .padding(.vertical, DesignSystem.Spacing.xs)
                            .padding(.horizontal, DesignSystem.Spacing.lg)
                            .background(isSelected ? DesignSystem.ColorToken.ink.opacity(0.1) : DesignSystem.ColorToken.cardSurface)
                            .id(data.fullMonthString)
                            .onTapGesture {
                                selectedMonthlyData = data
                            }

                            if data.id != salesAnalyticsViewModel.monthlyRevenue.last?.id {
                                Divider()
                                    .padding(.horizontal, DesignSystem.Spacing.lg)
                            }
                        }
                    }
                    // 強制刷新
                    .id("\(timeRange.displayText)-\(salesAnalyticsViewModel.salesOverview?.totalAmount ?? 0)-monthly")
                }
                .frame(height: min(CGFloat(salesAnalyticsViewModel.monthlyRevenue.count) * 40, 233))
                .onChange(of: selectedMonthlyData?.fullMonthString) {
                    if let monthString = selectedMonthlyData?.fullMonthString {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            scrollProxy.scrollTo(monthString, anchor: .center)
                        }
                    }
                }
            }
        }
    }
}
