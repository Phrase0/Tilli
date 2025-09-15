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
    
    init(session: Binding<SessionModel>) {
        self._viewModel = StateObject(wrappedValue: SessionDetailFromCalendarViewModel(session: session))
    }
    
    var body: some View {
        VStack(spacing: 0) {
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
                
                ProductPerformanceView(viewModel: viewModel.productPerformanceViewModel)
                    .tag(1)
                
                SalesAnalyticsView()
                    .tag(2)
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(viewModel.session.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.updateDataManagers(
                transactionDataManager: transactionDataManager,
                sessionDataManager: sessionDataManager
            )
            viewModel.loadData()
        }
    }
}
