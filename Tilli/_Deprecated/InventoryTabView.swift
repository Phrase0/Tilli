//
//  InventoryTabView.swift
//  Tilli
//
//  Created by Peiyun on 2025/1/12.
//

import SwiftUI

/// 庫存管理 Tab 入口頁面
/// 顯示場次列表，選擇後進入庫存管理詳情
struct InventoryTabView: View {
    @EnvironmentObject var eventDataManager: EventRepository
    @StateObject private var viewModel = InventoryTabViewModel()
    @State private var selectedSession: EventModel? = nil
    @State private var searchText = ""

    /// 當前顯示的場次列表
    private var displayedSessions: [EventModel] {
        viewModel.sortedFilteredEvents(by: searchText, from: eventDataManager.events)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    if displayedSessions.isEmpty {
                        emptyState
                    } else {
                        ForEach(displayedSessions) { session in
                            EventCardView(event: session, style: .simple)
                                .onTapGesture {
                                    selectedSession = session
                                }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("庫存管理")
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜尋場次")
            .navigationDestination(item: $selectedSession) { session in
                if let index = eventDataManager.events.firstIndex(where: { $0.id == session.id }) {
                    InventoryChangeView(event: eventDataManager.events[index])
                }
            }
            .onChange(of: eventDataManager.events) {
                // 檢查當前選中的場次是否還存在，若已被刪除則重置選擇
                if let selected = selectedSession,
                   !eventDataManager.events.contains(where: { $0.id == selected.id }) {
                    selectedSession = nil
                }
            }
        }
    }

    // MARK: - 空狀態（參考 SessionsView）

    private var emptyState: some View {
        Group {
            if searchText.isEmpty {
                // 完全沒有場次
                EmptyStateView(
                    systemImage: "shippingbox",
                    title: "尚無場次",
                    message: "請先在「場次」頁面新增場次"
                )
            } else {
                // 搜尋無結果
                EmptyStateView(
                    systemImage: "magnifyingglass",
                    title: "查無結果",
                    message: "找不到符合「\(searchText)」的場次"
                )
            }
        }
    }
}
