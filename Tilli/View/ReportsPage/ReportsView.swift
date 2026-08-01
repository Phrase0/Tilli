//
//  ReportsView.swift
//  Tilli
//
//  Created by Peiyun.
//

import SwiftUI

struct ReportsView: View {

    let event: EventModel

    @StateObject private var viewModel: ReportsViewModel
    @EnvironmentObject var transactionDataManager: TransactionRepository
    @EnvironmentObject var eventDataManager: EventRepository

    @State private var timeRange: ReportTimeRange
    @State private var showingShareSheet = false

    init(event: EventModel) {
        self.event = event
        self._viewModel = StateObject(wrappedValue: ReportsViewModel(event: event))
        self._timeRange = State(initialValue: ReportTimeRange(event: event))
    }

    var body: some View {
        VStack(spacing: 0) {
            ReportTimeRangeSelector(event: event, selectedRange: $timeRange)
                .padding(.horizontal, DesignSystem.Spacing.md)
                .padding(.top, DesignSystem.Spacing.xs)

            segmentedControl

            TabView(selection: $viewModel.selectedTab) {
                TransactionHistoryView(
                    transactionViewModel: viewModel.transactionViewModel,
                    event: .constant(event),
                    timeRange: timeRange
                )
                .tag(ReportsTab.transactions)

                ProductPerformanceView(
                    viewModel: viewModel.productPerformanceViewModel,
                    event: .constant(event),
                    timeRange: timeRange
                )
                .tag(ReportsTab.performance)

                SalesAnalyticsView(
                    viewModel: viewModel.salesAnalyticsViewModel,
                    event: .constant(event),
                    timeRange: timeRange
                )
                .tag(ReportsTab.analytics)
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
        }
        .background(DesignSystem.ColorToken.paper)
        .navigationTitle("reportsNavTitle")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                exportMenu
            }
        }
        .onAppear {
            viewModel.updateDataManagers(
                transactionDataManager: transactionDataManager,
                eventDataManager: eventDataManager
            )
            viewModel.loadAllData(timeRange: timeRange)
        }
        .onChange(of: timeRange.type) {
            viewModel.loadAllData(timeRange: timeRange)
        }
        .onChange(of: timeRange.customStart) {
            if timeRange.type == .custom {
                viewModel.loadAllData(timeRange: timeRange)
            }
        }
        .onChange(of: timeRange.customEnd) {
            if timeRange.type == .custom {
                viewModel.loadAllData(timeRange: timeRange)
            }
        }
        .shareSheet(
            isPresented: $showingShareSheet,
            activityItems: { viewModel.currentShareItems },
            excludedTypes: UIActivity.ActivityType.defaultExcludedTypes,
            onComplete: { completed in
                if completed {
                    viewModel.handleExportSuccess()
                }
            }
        )
        .alert("reportsExportSuccess", isPresented: $viewModel.showingExportSuccessAlert) {
            Button("commonConfirm") { }
        } message: {
            Text("reportsExportSuccessMessage")
        }
    }

    // MARK: - Segmented Control

    private var segmentedControl: some View {
        Picker("", selection: $viewModel.selectedTab) {
            // 交易明細
            Text("reportsTransactionTab").tag(ReportsTab.transactions)
            // 產品績效
            Text("reportsPerformanceTab").tag(ReportsTab.performance)
            // 銷售分析
            Text("reportsAnalyticsTab").tag(ReportsTab.analytics)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, DesignSystem.Spacing.md)
        .padding(.vertical, DesignSystem.Spacing.sm)
    }

    // MARK: - Export Menu

    @ViewBuilder
    private var exportMenu: some View {
        Menu {
            switch viewModel.selectedTab {
            case .transactions:
                Button {
                    viewModel.prepareExport(type: .transactionDetail)
                    showingShareSheet = true
                } label: {
                    // 交易明細
                    Label("reportsExportTransactionDetail", systemImage: "list.clipboard")
                }

            case .performance:
                Button {
                    viewModel.prepareExport(type: .productPerformanceAll)
                    showingShareSheet = true
                } label: {
                    // 全部匯出
                    Label("reportsExportAll", systemImage: "square.and.arrow.up.on.square")
                }

                Divider()

                Button {
                    viewModel.prepareExport(type: .topProducts)
                    showingShareSheet = true
                } label: {
                    // 熱門商品排行
                    Label("reportsExportTopProducts", systemImage: "chart.bar")
                }

                Button {
                    viewModel.prepareExport(type: .categoryAnalysis)
                    showingShareSheet = true
                } label: {
                    // 類別銷售匯總
                    Label("reportsExportCategoryAnalysis", systemImage: "folder")
                }

            case .analytics:
                Button {
                    viewModel.prepareExport(type: .salesAnalyticsAll)
                    showingShareSheet = true
                } label: {
                    // 全部匯出
                    Label("reportsExportAll", systemImage: "square.and.arrow.up.on.square")
                }

                Divider()

                Button {
                    viewModel.prepareExport(type: .hourlyAnalysis)
                    showingShareSheet = true
                } label: {
                    // 時段銷售分析
                    Label("reportsExportHourlyAnalysis", systemImage: "clock")
                }

                Button {
                    viewModel.prepareExport(type: .paymentMethod)
                    showingShareSheet = true
                } label: {
                    // 支付方式分析
                    Label("reportsExportPaymentMethod", systemImage: "creditcard")
                }

                Button {
                    viewModel.prepareExport(type: .dailyRevenueTrend)
                    showingShareSheet = true
                } label: {
                    // 日營收趨勢
                    Label("reportsExportDailyRevenue", systemImage: "chart.line.uptrend.xyaxis")
                }

                if event.dateType == .permanent {
                    Button {
                        viewModel.prepareExport(type: .monthlyRevenueTrend)
                        showingShareSheet = true
                    } label: {
                        // 月營收趨勢
                        Label("reportsExportMonthlyRevenue", systemImage: "calendar")
                    }
                }
            }
        } label: {
            Image(systemName: "square.and.arrow.up")
                .foregroundColor(
                    viewModel.isCurrentTabExportDisabled()
                        ? DesignSystem.ColorToken.muted
                        : DesignSystem.ColorToken.ink
                )
        }
        .disabled(viewModel.isCurrentTabExportDisabled())
    }
}
