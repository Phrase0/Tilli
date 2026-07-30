//
//  SessionsView.swift
//  Tilli
//
//  Created by Peiyun on 2025/4/22.
//

import SwiftUI

struct SessionsView: View {

    @EnvironmentObject var eventDataManager: EventRepository

    @State private var searchText = ""
    @State private var isNavigatingToAddSession = false
    @State private var editingSession: EventModel? = nil
    @State private var sessionToDelete: EventModel? = nil
    @State private var showDeleteConfirmation = false
    @State private var showBatchDeleteConfirmation = false

    @State private var selectedSession: EventModel? = nil

    @StateObject private var viewModel: EventsViewModel
    init() {
        _viewModel = StateObject(wrappedValue: EventsViewModel())
    }
    

    /// 當前顯示的場次列表（用於全選判斷）
    private var displayedSessions: [EventModel] {
        viewModel.sortedFilteredEvents(by: searchText, from: eventDataManager.events)
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
                                        Image(systemName: viewModel.selectedEventIds.contains(event.id) ? "checkmark.circle.fill" : "circle")
                                            .font(.title2)
                                            .foregroundColor(viewModel.selectedEventIds.contains(event.id) ? .blue : .gray)
                                    }

                                    sessionCard(event, showMenu: !viewModel.isSelectionMode)
                                }
                                .onTapGesture {
                                    if viewModel.isSelectionMode {
                                        viewModel.toggleSelection(eventId: session.id)
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
                        .disabled(eventDataManager.events.isEmpty)
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
                AddEventView(onSave: { newEvent in
                    viewModel.addEvent(newEvent, using: eventDataManager)
                    isNavigatingToAddSession = false
                })
            }
            .navigationDestination(item: $selectedSession) { session in
                if let index = eventDataManager.events.firstIndex(where: { $0.id == session.id }) {
                    EventDetailView(event: $eventDataManager.events[index])
                }
            }
            .navigationDestination(isPresented: Binding(
                get: { editingSession != nil },
                set: { isActive in
                    if !isActive { editingSession = nil }
                }
            )) {
                if let event = editingSession {
                    AddEventView(sessionToEdit: session, onSave: { updateEvent in
                        viewModel.updateEvent(updateEvent, using: eventDataManager)
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
                viewModel.deleteEvent(event, using: eventDataManager)
            }
            Button("取消", role: .cancel) { }
        } message: { session in
            Text("刪除後將同時移除底下的所有類別、商品，且無法復原，是否確定？")
        }
        .alert("確定要刪除 \(viewModel.selectedCount) 個場次嗎？", isPresented: $showBatchDeleteConfirmation) {
            Button("刪除", role: .destructive) {
                viewModel.deleteSelectedEvents(using: eventDataManager)
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text("刪除後將同時移除所有類別、商品，且無法復原，是否確定？")
        }
        .sheet(isPresented: $viewModel.showDuplicateEventDialog) {
            duplicateEventView
        }
    }

    // MARK: - 複製場次 View
    @ViewBuilder
    private var duplicateEventView: some View {
        NavigationView {
            Form {
                TextField("場次名稱", text: $viewModel.duplicateEventName)
                    .onChange(of: viewModel.duplicateEventName) {
                        viewModel.onEventNameChanged()
                    }

                // 場次類型選擇器
                Section {
                    Picker("場次類型", selection: $viewModel.duplicateEventDateType) {
                        Text("單日").tag(EventDateType.single)
                        Text("多日").tag(EventDateType.multi)
                        Text("無限期").tag(EventDateType.permanent)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: viewModel.duplicateEventDateType) { _, newType in
                        // 切換到多日時，自動設定結束日期為開始日期 +1 天
                        if newType == .multi {
                            viewModel.duplicateEventEndDate = Calendar.current.date(byAdding: .day, value: 1, to: viewModel.duplicateEventDate) ?? viewModel.duplicateEventDate
                        }
                    }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))

                // 動態日期選擇器
                Section {
                    switch viewModel.duplicateEventDateType {
                    case .single:
                        DatePicker("日期", selection: $viewModel.duplicateEventDate, displayedComponents: .date)

                    case .multi:
                        DatePicker(
                            "開始日期",
                            selection: $viewModel.duplicateEventDate,
                            displayedComponents: .date
                        )
                        .onChange(of: viewModel.duplicateEventDate) { _, newStartDate in
                            // 結束日期必須至少是開始日期的隔天
                            if viewModel.duplicateEventEndDate <= newStartDate {
                                viewModel.duplicateEventEndDate = Calendar.current.date(byAdding: .day, value: 1, to: newStartDate) ?? newStartDate
                            }
                        }

                        DatePicker(
                            "結束日期",
                            selection: $viewModel.duplicateEventEndDate,
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
                        DatePicker("開始日期", selection: $viewModel.duplicateEventDate, displayedComponents: .date)

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
                        viewModel.cancelDuplicateEvent()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("確定") {
                        viewModel.confirmDuplicateEvent(using: eventDataManager)
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
    private func sessionCard(_ event: EventModel, showMenu: Bool = true) -> some View {
        if showMenu {
            EventCardView(
                event: session,
                style: .standard,
                onDuplicate: { viewModel.startDuplicateEvent(event) },
                onEdit: { editingSession = session },
                onDelete: {
                    sessionToDelete = session
                    showDeleteConfirmation = true
                }
            )
        } else {
            EventCardView(event: session, style: .simple)
        }
    }
}
