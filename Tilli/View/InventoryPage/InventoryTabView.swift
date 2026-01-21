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
    @EnvironmentObject var sessionDataManager: SessionRepository
    @StateObject private var viewModel = InventoryTabViewModel()
    @State private var selectedSession: SessionModel? = nil
    @State private var searchText = ""

    /// 當前顯示的場次列表
    private var displayedSessions: [SessionModel] {
        viewModel.sortedFilteredSessions(by: searchText, from: sessionDataManager.sessions)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    if displayedSessions.isEmpty {
                        emptyState
                    } else {
                        ForEach(displayedSessions) { session in
                            SessionCardView(session: session, style: .simple)
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
                if let index = sessionDataManager.sessions.firstIndex(where: { $0.id == session.id }) {
                    InventoryChangeView(session: sessionDataManager.sessions[index])
                }
            }
            .onChange(of: sessionDataManager.sessions) {
                // 檢查當前選中的場次是否還存在，若已被刪除則重置選擇
                if let selected = selectedSession,
                   !sessionDataManager.sessions.contains(where: { $0.id == selected.id }) {
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
