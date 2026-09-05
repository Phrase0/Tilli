//
//  ReportsView.swift
//  Tilli
//
//  Created by Peiyun.
//

import SwiftUI

struct ReportsView: View {

    let event: EventModel

    @ObservedObject var viewModel: ReportsViewModel
    @EnvironmentObject var transactionDataManager: TransactionRepository
    @EnvironmentObject var eventDataManager: EventRepository

    @State private var timeRange: ReportTimeRange
    @Binding var showingShareSheet: Bool

    init(event: EventModel, viewModel: ReportsViewModel, showingShareSheet: Binding<Bool>) {
        self.event = event
        self.viewModel = viewModel
        self._timeRange = State(initialValue: ReportTimeRange(event: event))
        self._showingShareSheet = showingShareSheet
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
}
