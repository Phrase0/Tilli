//
//  SessionsView.swift
//  Tilli
//
//  Created by Peiyun on 2025/4/22.
//

import SwiftUI

struct SessionsView: View {

    @EnvironmentObject var sessionDataManager: SessionDataManager

    @State private var searchText = ""
    @State private var isNavigatingToAddSession = false
    @State private var editingSession: SessionModel? = nil
    @State private var sessionToDelete: SessionModel? = nil
    @State private var showDeleteConfirmation = false
    @State private var showBatchDeleteConfirmation = false

    @State private var selectedSession: SessionModel? = nil

    @StateObject private var viewModel: SessionViewModel
    init() {
        _viewModel = StateObject(wrappedValue: SessionViewModel())
    }
    

    /// 當前顯示的場次列表（用於全選判斷）
    private var displayedSessions: [SessionModel] {
        viewModel.sortedFilteredSessions(by: searchText, from: sessionDataManager.sessions)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if displayedSessions.isEmpty {
                            // 空狀態顯示
                            if searchText.isEmpty {
                                // 完全沒有場次
                                EmptyStateView(
                                    systemImage: "calendar.badge.plus",
                                    title: "尚無場次",
                                    message: "點擊右上角「+」按鈕新增第一個場次"
                                )
                            } else {
                                // 搜尋無結果
                                EmptyStateView(
                                    systemImage: "magnifyingglass",
                                    title: "查無結果",
                                    message: "找不到符合「\(searchText)」的場次"
                                )
                            }
                        } else {
                            // 有場次時顯示列表
                            ForEach(displayedSessions) { session in
                                HStack(spacing: 12) {
                                    // 選取模式下顯示勾選框
                                    if viewModel.isSelectionMode {
                                        Image(systemName: viewModel.selectedSessionIds.contains(session.id) ? "checkmark.circle.fill" : "circle")
                                            .font(.title2)
                                            .foregroundColor(viewModel.selectedSessionIds.contains(session.id) ? .blue : .gray)
                                    }

                                    sessionCard(session, showMenu: !viewModel.isSelectionMode)
                                }
                                .onTapGesture {
                                    if viewModel.isSelectionMode {
                                        viewModel.toggleSelection(sessionId: session.id)
                                    } else {
                                        selectedSession = session
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                    // 選取模式時底部留空間給操作列
                    .padding(.bottom, viewModel.isSelectionMode ? 70 : 0)
                }

                // 選取模式底部操作列
                if viewModel.isSelectionMode {
                    selectionActionBar
                }
            }
            .navigationTitle("場次")
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜尋場次")
            .toolbar {
                // 左上角：選取按鈕（非選取模式）或取消按鈕（選取模式）
                ToolbarItem(placement: .navigationBarLeading) {
                    if viewModel.isSelectionMode {
                        Button("取消") {
                            viewModel.exitSelectionMode()
                        }
                    } else {
                        Button("選取") {
                            viewModel.enterSelectionMode()
                        }
                        .disabled(sessionDataManager.sessions.isEmpty)
                    }
                }

                // 右上角：新增按鈕（非選取模式時顯示）
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !viewModel.isSelectionMode {
                        Button {
                            isNavigatingToAddSession = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .navigationDestination(isPresented: $isNavigatingToAddSession) {
                AddSessionView(onSave: { newSession in
                    viewModel.addSession(newSession, using: sessionDataManager)
                    isNavigatingToAddSession = false
                })
            }
            .navigationDestination(item: $selectedSession) { session in
                if let index = sessionDataManager.sessions.firstIndex(where: { $0.id == session.id }) {
                    SessionDetailView(session: $sessionDataManager.sessions[index])
                }
            }
            .navigationDestination(isPresented: Binding(
                get: { editingSession != nil },
                set: { isActive in
                    if !isActive { editingSession = nil }
                }
            )) {
                if let session = editingSession {
                    AddSessionView(sessionToEdit: session, onSave: { updatedSession in
                        viewModel.updateSession(updatedSession, using: sessionDataManager)
                        editingSession = nil
                    })
                }
            }
            .onAppear {
                // SessionDataManager 會自動管理和更新 sessions 數據
            }
            .toolbar(viewModel.isSelectionMode ? .hidden : .visible, for: .tabBar)
            .animation(.easeInOut(duration: 0.3), value: viewModel.isSelectionMode)
        }
        .alert("確定要刪除這個場次嗎？", isPresented: $showDeleteConfirmation, presenting: sessionToDelete) { session in
            Button("刪除", role: .destructive) {
                viewModel.deleteSession(session, using: sessionDataManager)
            }
            Button("取消", role: .cancel) { }
        } message: { session in
            Text("刪除後將同時移除底下的所有類別、商品，且無法復原，是否確定？")
        }
        .alert("確定要刪除 \(viewModel.selectedCount) 個場次嗎？", isPresented: $showBatchDeleteConfirmation) {
            Button("刪除", role: .destructive) {
                viewModel.deleteSelectedSessions(using: sessionDataManager)
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text("刪除後將同時移除所有類別、商品，且無法復原，是否確定？")
        }
        .sheet(isPresented: $viewModel.showDuplicateSessionDialog) {
            duplicateSessionView
        }
    }

    // MARK: - 複製場次 View
    @ViewBuilder
    private var duplicateSessionView: some View {
        NavigationView {
            Form {
                TextField("場次名稱", text: $viewModel.duplicateSessionName)
                    .onChange(of: viewModel.duplicateSessionName) {
                        viewModel.onSessionNameChanged()
                    }

                // 場次類型選擇器
                Section {
                    Picker("場次類型", selection: $viewModel.duplicateSessionDateType) {
                        Text("單日").tag(SessionDateType.single)
                        Text("多日").tag(SessionDateType.multi)
                        Text("無限期").tag(SessionDateType.permanent)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: viewModel.duplicateSessionDateType) { _, newType in
                        // 切換到多日時，自動設定結束日期為開始日期 +1 天
                        if newType == .multi {
                            viewModel.duplicateSessionEndDate = Calendar.current.date(byAdding: .day, value: 1, to: viewModel.duplicateSessionDate) ?? viewModel.duplicateSessionDate
                        }
                    }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))

                // 動態日期選擇器
                Section {
                    switch viewModel.duplicateSessionDateType {
                    case .single:
                        DatePicker("日期", selection: $viewModel.duplicateSessionDate, displayedComponents: .date)

                    case .multi:
                        DatePicker(
                            "開始日期",
                            selection: $viewModel.duplicateSessionDate,
                            displayedComponents: .date
                        )
                        .onChange(of: viewModel.duplicateSessionDate) { _, newStartDate in
                            // 結束日期必須至少是開始日期的隔天
                            if viewModel.duplicateSessionEndDate <= newStartDate {
                                viewModel.duplicateSessionEndDate = Calendar.current.date(byAdding: .day, value: 1, to: newStartDate) ?? newStartDate
                            }
                        }

                        DatePicker(
                            "結束日期",
                            selection: $viewModel.duplicateSessionEndDate,
                            in: viewModel.duplicateEndDateRange,
                            displayedComponents: .date
                        )

                        HStack {
                            Image(systemName: "info.circle")
                                .foregroundColor(.blue)
                                .font(.caption)
                            Text("多日場次最多 31 天")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                    case .permanent:
                        DatePicker("開始日期", selection: $viewModel.duplicateSessionDate, displayedComponents: .date)

                        HStack {
                            Image(systemName: "infinity")
                                .foregroundColor(.purple)
                            Text("此場次無結束日期")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("複製場次")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        viewModel.cancelDuplicateSession()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("確定") {
                        viewModel.confirmDuplicateSession(using: sessionDataManager)
                    }
                    .disabled(viewModel.isDuplicateButtonDisabled)
                }
            }
        }
        .presentationDetents([.fraction(0.55)])
    }
    
    // MARK: - 選取模式底部操作列
    private var selectionActionBar: some View {
        HStack {
            // 全選/取消全選按鈕
            Button {
                if viewModel.isAllSelected(sessions: displayedSessions) {
                    viewModel.deselectAll()
                } else {
                    viewModel.selectAll(sessions: displayedSessions)
                }
            } label: {
                Text(viewModel.isAllSelected(sessions: displayedSessions) ? "取消全選" : "全選")
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .contentShape(Rectangle())
            }
            .disabled(displayedSessions.isEmpty)

            Spacer()

            // 刪除按鈕
            Button {
                showBatchDeleteConfirmation = true
            } label: {
                Text("刪除 (\(viewModel.selectedCount))")
                    .foregroundColor(viewModel.isDeleteButtonDisabled ? .gray : .red)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .contentShape(Rectangle())
            }
            .disabled(viewModel.isDeleteButtonDisabled)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
        .contentShape(Rectangle())
    }

    // MARK: - 卡片 View
    @ViewBuilder
    private func sessionCard(_ session: SessionModel, showMenu: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(session.title)
                        .font(.headline)
                        .lineLimit(1)

                    Text(session.displayDateRange)
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 12) {
                    if showMenu {
                        Menu {
                            Button {
                                viewModel.startDuplicateSession(session)
                            } label: {
                                Label("複製場次", systemImage: "doc.on.doc")
                            }

                            Button {
                                editingSession = session
                            } label: {
                                Label("編輯", systemImage: "pencil")
                            }

                            Button(role: .destructive) {
                                sessionToDelete = session
                                showDeleteConfirmation = true
                            } label: {
                                Label("刪除", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .rotationEffect(.degrees(90))
                                .foregroundColor(.gray)
                                .padding(8)
                        }
                    }

                    Text(session.status.localizedDescription)
                        .font(.caption)
                        .foregroundColor(session.status.textColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(session.status.color)
                        .clipShape(Capsule())
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(session.status == .ongoing ? Color.blue.opacity(0.1) : Color.white)
        )
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
    }
}
