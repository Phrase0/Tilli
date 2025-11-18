//
//  SessionDetailFromCalendarView.swift
//  Tilli
//
//  Created by Peiyun on 2025/9/8.
//

import SwiftUI

struct SessionDetailFromCalendarView: View {
    @StateObject private var viewModel: SessionDetailFromCalendarViewModel
    @EnvironmentObject var sessionDataManager: SessionDataManager
    @EnvironmentObject var transactionDataManager: TransactionDataManager
    @Environment(\.dismiss) private var dismiss

    @State private var showingShareSheet = false
    @State private var timeRange: ReportTimeRange

    init(session: Binding<SessionModel>) {
        self._viewModel = StateObject(wrappedValue: SessionDetailFromCalendarViewModel(session: session))

        // 初始化時間範圍
        self._timeRange = State(initialValue: ReportTimeRange(session: session.wrappedValue))
    }

    var body: some View {
        VStack(spacing: 0) {
            // 時間範圍選擇器
            ReportTimeRangeSelector(session: viewModel.session, selectedRange: $timeRange)
                .padding(.horizontal)
                .padding(.top, 12)

            // 自定義 Picker
            HStack {
                ForEach(0..<viewModel.tabTitles.count, id: \.self) { index in
                    Button(action: {
                        viewModel.selectTab(index)
                    }) {
                        VStack(spacing: 6) {
                            Text(viewModel.tabTitles[index])
                                .font(.subheadline)
                                .foregroundColor(viewModel.selectedTab == index ? .blue : .gray)
                                .fontWeight(viewModel.selectedTab == index ? .semibold : .regular)
                            
                            Rectangle()
                                .fill(viewModel.selectedTab == index ? Color.blue : Color.clear)
                                .frame(height: 2)
                                .scaleEffect(x: viewModel.selectedTab == index ? 1.0 : 0.8, y: 1.0)
                                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: viewModel.selectedTab)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            
            Divider()
            
            // 內容區域
            TabView(selection: $viewModel.selectedTab) {
                TransactionHistoryView(
                    transactionViewModel: viewModel.transactionViewModel,
                    session: $viewModel.session
                )
                .tag(0)
                
                ProductPerformanceView(
                    viewModel: viewModel.productPerformanceViewModel,
                    session: $viewModel.session
                )
                    .tag(1)
                
                SalesAnalyticsView(
                    viewModel: viewModel.salesAnalyticsViewModel,
                    session: $viewModel.session
                )
                    .tag(2)
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(viewModel.session.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: {
                    dismiss()
                }) {
                    Image(systemName: "chevron.left")
                        .foregroundColor(.blue)
                }
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    showingShareSheet = true
                }) {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(viewModel.isCurrentTabExportDisabled())
            }
        }
        .onAppear {
            viewModel.updateDataManagers(
                transactionDataManager: transactionDataManager,
                sessionDataManager: sessionDataManager
            )
            viewModel.loadData()
        }
        .shareSheet(
            isPresented: $showingShareSheet,
            activityItems: viewModel.getCurrentTabShareItems(),
            excludedTypes: UIActivity.ActivityType.defaultExcludedTypes,
            onComplete: { completed in
                if completed {
                    viewModel.handleCurrentTabExportSuccess()
                }
            }
        )
    }

}
