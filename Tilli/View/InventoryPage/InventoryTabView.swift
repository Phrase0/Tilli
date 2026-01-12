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
    @EnvironmentObject var sessionDataManager: SessionDataManager
    @State private var selectedSession: SessionModel? = nil
    @State private var searchText = ""

    /// 篩選後的場次列表（只顯示進行中的場次）
    private var activeSessions: [SessionModel] {
        sessionDataManager.sessions
            .filter { session in
                // 搜尋篩選
                if !searchText.isEmpty {
                    return session.title.localizedCaseInsensitiveContains(searchText)
                }
                return true
            }
            .sorted { $0.startDate > $1.startDate }
    }

    var body: some View {
        NavigationStack {
            Group {
                if activeSessions.isEmpty {
                    emptyState
                } else {
                    sessionList
                }
            }
            .navigationTitle("庫存管理")
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜尋場次")
            .navigationDestination(item: $selectedSession) { session in
                if let index = sessionDataManager.sessions.firstIndex(where: { $0.id == session.id }) {
                    InventoryChangeView(session: sessionDataManager.sessions[index])
                }
            }
        }
    }

    // MARK: - 空狀態

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "shippingbox")
                .font(.system(size: 60))
                .foregroundColor(.gray.opacity(0.5))

            Text("尚無場次")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("請先在「場次」頁面新增場次")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - 場次列表

    private var sessionList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(activeSessions) { session in
                    sessionCard(session)
                        .onTapGesture {
                            selectedSession = session
                        }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - 場次卡片

    private func sessionCard(_ session: SessionModel) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                Text(session.title)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text(session.displayDateRange)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // 狀態標籤
            Text(session.status.localizedDescription)
                .font(.caption)
                .foregroundColor(session.status.textColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(session.status.color)
                .clipShape(Capsule())

            Image(systemName: "chevron.right")
                .foregroundColor(.gray)
                .font(.caption)
        }
        .padding()
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}
