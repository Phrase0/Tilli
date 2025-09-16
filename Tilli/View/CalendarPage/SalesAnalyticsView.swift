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
    @State private var showingShareSheet = false

    init(viewModel: SalesAnalyticsViewModel, session: Binding<SessionModel>) {
        self.salesAnalyticsViewModel = viewModel
        self._session = session
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if salesAnalyticsViewModel.salesOverview?.totalTransactions == 0 || salesAnalyticsViewModel.salesOverview == nil {
                    EmptyStateView(
                        systemImage: "chart.line.uptrend.xyaxis",
                        title: "尚無銷售分析",
                        message: "完成結帳後，銷售分析會顯示在這裡"
                    )
                } else {
                    VStack(spacing: 20) {
                        // 總銷售額區塊
                        salesSummaryView

                        // 時間分布圖與詳細記錄（合併為一個卡片）
                        timeDistributionWithDetailView

                        // 支付方式分布
                        paymentMethodDistribution
                    }
                }
            }
            .padding()
        }

        .onAppear {
            salesAnalyticsViewModel.loadData()
        }
        .refreshable {
            salesAnalyticsViewModel.loadData()
        }
        .onChange(of: session.transactions) {
            salesAnalyticsViewModel.loadData()
        }
        .background(Color(.systemGray6))
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    showingShareSheet = true
                }) {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(salesAnalyticsViewModel.salesOverview?.totalTransactions == 0 || salesAnalyticsViewModel.salesOverview == nil)
            }
        }
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
            Text("NT$\(String(format: "%.0f", salesAnalyticsViewModel.salesOverview?.totalAmount ?? 0).addingThousandsSeparator)")
                .font(.title2)
                .fontWeight(.bold)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
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

    // MARK: - 時間分布圖與詳細記錄合併視圖
    private var timeDistributionWithDetailView: some View {
        VStack(alignment: .leading, spacing: 0) {
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
                        Text("\(String(format: "%.0f", salesAnalyticsViewModel.salesOverview?.peakHourAmount ?? 0)) 元")
                            .font(.caption2)
                            .foregroundColor(.secondary)
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

                                Text("\(String(format: "%.0f", data.amount).addingThousandsSeparator)")
                                    .font(.system(size: 14, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .center)

                                Text("\(data.transactions)")
                                    .font(.system(size: 14))
                                    .frame(maxWidth: .infinity, alignment: .center)

                                Text("\(String(format: "%.0f", data.avgPrice))")
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
    }

    // MARK: - 自定義柱狀圖（適用於 iOS 16 以下）
    private var customBarChart: some View {
        let maxAmount = salesAnalyticsViewModel.hourlyData.max { $0.amount < $1.amount }?.amount ?? 1

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
                        height: CGFloat(data.amount) / CGFloat(maxAmount) * 150
                    )
            }
        }
        .frame(height: 200)
        .padding(.horizontal)
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
                .stroke(Color.red, lineWidth: 40)
                .rotationEffect(.degrees(-90))

            Circle()
                .trim(from: ratio, to: 1.0)
                .stroke(Color.yellow, lineWidth: 40)
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 150, height: 150)
    }
}
