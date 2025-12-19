//
//  SalesAnalyticsView.swift
//  Tilli
//
//  Created by Peiyun on 2025/9/16.
//

import SwiftUI
import Charts
import UniformTypeIdentifiers

struct SalesAnalyticsView: View {
    @ObservedObject var salesAnalyticsViewModel: SalesAnalyticsViewModel
    @Binding var session: SessionModel
    let timeRange: ReportTimeRange
    @State private var showingShareSheet = false

    init(viewModel: SalesAnalyticsViewModel, session: Binding<SessionModel>, timeRange: ReportTimeRange) {
        self.salesAnalyticsViewModel = viewModel
        self._session = session
        self.timeRange = timeRange
    }

    var body: some View {
        Group {
            if salesAnalyticsViewModel.salesOverview?.totalTransactions == 0 || salesAnalyticsViewModel.salesOverview == nil {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        EmptyStateView(
                            systemImage: "chart.line.uptrend.xyaxis",
                            title: "尚無銷售分析",
                            message: "完成結帳後，銷售分析會顯示在這裡"
                        )
                    }
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        VStack(spacing: 20) {
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
                    .padding()
                }
            }
        }
        .refreshable {
            salesAnalyticsViewModel.loadData(timeRange: timeRange)
        }
        .background(Color(.systemGray6))
        .alert("CSV 導出成功", isPresented: $salesAnalyticsViewModel.showingExportAlert) {
            Button("確定") { }
        } message: {
            Text("銷售分析報告已成功導出為 CSV 檔案")
        }
        .shareSheet(
            isPresented: $showingShareSheet,
            activityItems: [
                salesAnalyticsViewModel.createHourlyAnalysisCSVFileURL(),
                salesAnalyticsViewModel.createPaymentMethodCSVFileURL()
            ],
            excludedTypes: UIActivity.ActivityType.defaultExcludedTypes,
            onComplete: { completed in
                if completed {
                    salesAnalyticsViewModel.showExportSuccessAlert()
                }
            }
        )
    }

    // MARK: - 總銷售額視圖
    private var salesSummaryView: some View {
        HStack(spacing: 15) {
            salesCard
            transactionsCard
        }
    }

    // 銷售額卡片
    private var salesCard: some View {
        VStack {
            Text("總銷售額")
                .font(.caption)
                .foregroundColor(.secondary)
            if let totalAmount = salesAnalyticsViewModel.salesOverview?.totalAmount {
                Text(MoneyHelper.format(totalAmount, currencyCode: session.currency))
                    .font(.title2)
                    .fontWeight(.bold)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            } else {
                Text(MoneyHelper.format(0, currencyCode: session.currency))
                    .font(.title2)
                    .fontWeight(.bold)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 60)
        .padding()
        .background(Color.white)
        .cornerRadius(12)
    }

    // 交易筆數卡片
    private var transactionsCard: some View {
        VStack {
            Text("交易筆數")
                .font(.caption)
                .foregroundColor(.secondary)
            Text("\(salesAnalyticsViewModel.salesOverview?.totalTransactions ?? 0)")
                .font(.title2)
                .fontWeight(.bold)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 60)
        .padding()
        .background(Color.white)
        .cornerRadius(12)
    }

    // MARK: - 支付方式分布
    private var paymentMethodDistribution: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("支付方式分布")
                .font(.headline)
                .padding(.horizontal)
                .padding(.vertical)

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
            .padding(.vertical, 20)

            // 支付方式詳情
            VStack(spacing: 0) {
                HStack {
                    Text("支付方式")
                        .font(.caption)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text("交易數")
                        .font(.caption)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity, alignment: .center)

                    Text("占比")
                        .font(.caption)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 20)
                .background(Color(.systemGray6))

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

                        Text("\(method.transactions)")
                            .font(.system(size: 14))
                            .frame(maxWidth: .infinity, alignment: .center)

                        Text("\(method.percentage)%")
                            .font(.system(size: 14))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 20)
                    .background(Color.white)

                    if method.id != salesAnalyticsViewModel.paymentMethodData.last?.id {
                        Divider()
                            .padding(.horizontal, 20)
                    }
                }
            }
        }
        .background(Color.white)
        .cornerRadius(12)
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
                .stroke(Color.pink, lineWidth: 40)
                .rotationEffect(.degrees(-90))

            Circle()
                .trim(from: ratio, to: 1.0)
                .stroke(Color.purple, lineWidth: 40)
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 150, height: 150)
    }
    
    // MARK: - 時間分布圖與詳細記錄合併視圖
    private var timeDistributionWithDetailView: some View {
        let content = VStack(alignment: .leading, spacing: 0) {
            // 圖表部分
            VStack(alignment: .leading) {
                Text("時間分布圖")
                    .font(.headline)
                    .padding(.horizontal)
                    .padding(.vertical)

                if #available(iOS 16.0, *) {
                    barChartView
                } else {
                    // iOS 16 以下的替代方案
                    customBarChart
                }

                // 圖表說明
                HStack {
                    VStack(alignment: .leading) {
                        Text("最高銷售額")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        if let peakAmount = salesAnalyticsViewModel.salesOverview?.peakHourAmount {
                            Text(MoneyHelper.format(peakAmount, currencyCode: session.currency))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        } else {
                            Text(MoneyHelper.format(0, currencyCode: session.currency))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    VStack(alignment: .trailing) {
                        Text("總交易數")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(salesAnalyticsViewModel.salesOverview?.totalTransactions ?? 0)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
            }

            // 詳細記錄表格（直接連接）
            VStack(spacing: 0) {
                // 表頭
                HStack {
                    Text("時段")
                        .font(.caption)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text("銷售額")
                        .font(.caption)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity, alignment: .center)

                    Text("交易數")
                        .font(.caption)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity, alignment: .center)

                    Text("平均客單價")
                        .font(.caption)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 20)
                .background(Color(.systemGray6))

                // 可滾動的數據列表
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(salesAnalyticsViewModel.hourlyData) { data in
                            HStack {
                                Text(data.hourString)
                                    .font(.system(size: 14, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                Text(MoneyHelper.format(data.amount, currencyCode: session.currency))
                                    .font(.system(size: 14, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .center)

                                Text("\(data.transactions)")
                                    .font(.system(size: 14))
                                    .frame(maxWidth: .infinity, alignment: .center)

                                Text(MoneyHelper.format(data.avgPrice, currencyCode: session.currency))
                                    .font(.system(size: 14, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 20)
                            .background(Color.white)

                            if data.id != salesAnalyticsViewModel.hourlyData.last?.id {
                                Divider()
                                    .padding(.horizontal, 20)
                            }
                        }
                    }
                }
                .frame(height: 200)
            }
        }
        .background(Color.white)
        .cornerRadius(12)

        return content
    }

    // MARK: - Bar Chart View (iOS 16+)
    @available(iOS 16.0, *)
    private var barChartView: some View {
        Chart {
            ForEach(salesAnalyticsViewModel.hourlyData) { data in
                BarMark(
                    x: .value("時間", data.hourString),
                    y: .value("金額", data.amount)
                )
                .foregroundStyle(.blue.gradient)
            }
        }
        .chartXAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel() {
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
        .padding(.horizontal)
    }
    
    // MARK: - 自定義柱狀圖（適用於 iOS 16 以下）
    private var customBarChart: some View {
        let maxAmount = salesAnalyticsViewModel.hourlyData.max { $0.amount < $1.amount }?.amount ?? Decimal(1)

        return HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(salesAnalyticsViewModel.hourlyData.enumerated()), id: \.offset) { index, data in
                Rectangle()
                    .fill(LinearGradient(
                        colors: [.blue, .cyan],
                        startPoint: .bottom,
                        endPoint: .top
                    ))
                    .frame(
                        width: 8,
                        height: CGFloat(MoneyHelper.toUIDouble(data.amount)) / CGFloat(MoneyHelper.toUIDouble(maxAmount)) * 150
                    )
            }
        }
        .frame(height: 200)
        .padding(.horizontal)
    }

    // MARK: - Revenue Trend

    /// 是否顯示營收趨勢（單日不顯示，天數 > 1 才顯示）
    private var shouldShowRevenueTrend: Bool {
        session.dateType != .single && timeRange.dayCount > 1
    }

    /// 營收趨勢視圖
    private var revenueTrendView: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text("營收趨勢")
                    .font(.headline)

                Spacer()

                // 超過 90 天顯示切換按鈕
                if timeRange.dayCount > 90 {
                    Picker("視圖", selection: $salesAnalyticsViewModel.trendViewMode) {
                        Text("每日").tag(SalesAnalyticsViewModel.TrendViewMode.daily)
                        Text("每月").tag(SalesAnalyticsViewModel.TrendViewMode.monthly)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 120)
                }
            }
            .padding(.horizontal)
            .padding(.top)

            // 圖表區域
            if timeRange.dayCount > 90 && salesAnalyticsViewModel.trendViewMode == .monthly {
                // 每月視圖
                monthlyRevenueChart
            } else {
                // 每日視圖
                dailyRevenueChart
            }

            // 營收明細列表（≤90天顯示）
            if timeRange.dayCount <= 90 {
                revenueTrendDetailList
            }
        }
        .background(Color.white)
        .cornerRadius(12)
    }

    /// 每日營收圖表
    private var dailyRevenueChart: some View {
        Group {
            if timeRange.dayCount <= 7 {
                // ≤7天：柱狀圖
                dailyBarChart
            } else {
                // >7天：折線圖
                if #available(iOS 16.0, *) {
                    dailyLineChart
                } else {
                    dailyBarChart // iOS 15 fallback
                }
            }
        }
    }

    /// 每日柱狀圖
    private var dailyBarChart: some View {
        let maxAmount = salesAnalyticsViewModel.maxDailyAmount

        return VStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(salesAnalyticsViewModel.dailyRevenue) { data in
                    VStack(spacing: 4) {
                        // 金額標籤（≤7天時顯示）
                        if timeRange.dayCount <= 7 {
                            Text(MoneyHelper.format(data.amount, currencyCode: session.currency))
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                        }

                        // 柱狀
                        RoundedRectangle(cornerRadius: 4)
                            .fill(LinearGradient(
                                colors: [.blue, .cyan],
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
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: timeRange.dayCount <= 7 ? 180 : 150)
            .padding(.horizontal)
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
                .foregroundStyle(.blue)

                AreaMark(
                    x: .value("日期", data.date),
                    y: .value("金額", MoneyHelper.toUIDouble(data.amount))
                )
                .foregroundStyle(.blue.opacity(0.1))
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: max(1, timeRange.dayCount / 7))) { value in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month().day())
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading)
        }
        .frame(height: 200)
        .padding(.horizontal)
    }

    /// 每月營收圖表
    private var monthlyRevenueChart: some View {
        let maxAmount = salesAnalyticsViewModel.maxMonthlyAmount

        return VStack(spacing: 8) {
            ForEach(salesAnalyticsViewModel.monthlyRevenue) { data in
                HStack {
                    Text(data.fullMonthString)
                        .font(.system(size: 12))
                        .frame(width: 60, alignment: .leading)

                    GeometryReader { geometry in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(LinearGradient(
                                colors: [.purple, .pink],
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

                    Text(MoneyHelper.format(data.amount, currencyCode: session.currency))
                        .font(.system(size: 12, design: .monospaced))
                        .frame(width: 80, alignment: .trailing)
                }
            }
        }
        .padding(.horizontal)
        .padding(.bottom)
    }

    /// 營收趨勢明細列表
    private var revenueTrendDetailList: some View {
        VStack(spacing: 0) {
            // 表頭
            HStack {
                Text("日期")
                    .font(.caption)
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("交易數")
                    .font(.caption)
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity, alignment: .center)

                Text("營收")
                    .font(.caption)
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 20)
            .background(Color(.systemGray6))

            // 數據列表
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

                            Text(MoneyHelper.format(data.amount, currencyCode: session.currency))
                                .font(.system(size: 14, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 20)
                        .background(Color.white)

                        if data.id != salesAnalyticsViewModel.dailyRevenue.last?.id {
                            Divider()
                                .padding(.horizontal, 20)
                        }
                    }
                }
            }
            .frame(height: min(CGFloat(salesAnalyticsViewModel.dailyRevenue.count) * 40, 233))
        }
    }
}
