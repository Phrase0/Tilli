//
//  EventsView.swift
//  Tilli
//
//  Created by Peiyun on 2025/7/29.
//

import SwiftUI

enum EventsDisplayMode: String, CaseIterable {
    case list
    case calendar
}

struct EventsView: View {

    @EnvironmentObject var sessionDataManager: SessionRepository
    @StateObject private var viewModel = SessionViewModel()

    @State private var displayMode: EventsDisplayMode = .list
    @State private var searchText = ""
    @State private var showAddSessionSheet = false
    @State private var editingSession: SessionModel? = nil
    @State private var sessionToDelete: SessionModel? = nil
    @State private var showDeleteConfirmation = false
    @State private var showBatchDeleteConfirmation = false
    @State private var selectedSession: SessionModel? = nil

    private var displayedSessions: [SessionModel] {
        viewModel.sortedFilteredSessions(by: searchText, from: sessionDataManager.sessions)
    }

    private var ongoingSessions: [SessionModel] {
        displayedSessions.filter { $0.status == .ongoing }
    }

    private var upcomingSessions: [SessionModel] {
        displayedSessions.filter { $0.status == .upcoming }
    }

    private var completedSessions: [SessionModel] {
        displayedSessions.filter { $0.status == .completed }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                segmentedControl

                switch displayMode {
                case .list:
                    listContent
                case .calendar:
                    calendarPlaceholder
                }
            }
            .background(DesignSystem.ColorToken.paper)
            // 場次
            .navigationTitle("eventsPageTitle")
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .automatic),
                // 搜尋場次
                prompt: Text("eventsSearchPrompt")
            )
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if displayMode == .list {
                        if viewModel.isSelectionMode {
                            // 取消
                            Button("commonCancel") {
                                viewModel.exitSelectionMode()
                            }
                        } else {
                            // 選取
                            Button("eventsSelect") {
                                viewModel.enterSelectionMode()
                            }
                            .disabled(sessionDataManager.sessions.isEmpty)
                        }
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    if !viewModel.isSelectionMode {
                        Button {
                            showAddSessionSheet = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .navigationDestination(item: $selectedSession) { session in
                if let index = sessionDataManager.sessions.firstIndex(where: { $0.id == session.id }) {
                    SessionDetailView(session: $sessionDataManager.sessions[index])
                }
            }
            .toolbar(viewModel.isSelectionMode ? .hidden : .visible, for: .tabBar)
            .animation(.easeInOut(duration: 0.3), value: viewModel.isSelectionMode)
        }
        .sheet(isPresented: $showAddSessionSheet) {
            NavigationStack {
                AddSessionView(onSave: { newSession in
                    viewModel.addSession(newSession, using: sessionDataManager)
                    showAddSessionSheet = false
                })
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $editingSession) { session in
            NavigationStack {
                AddSessionView(sessionToEdit: session, onSave: { updatedSession in
                    viewModel.updateSession(updatedSession, using: sessionDataManager)
                    editingSession = nil
                })
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        // 確定要刪除這個場次嗎？
        .alert("eventsDeleteConfirmTitle", isPresented: $showDeleteConfirmation, presenting: sessionToDelete) { session in
            // 刪除
            Button("commonDelete", role: .destructive) {
                viewModel.deleteSession(session, using: sessionDataManager)
            }
            // 取消
            Button("commonCancel", role: .cancel) { }
        } message: { _ in
            // 刪除後將同時移除底下的所有類別、商品，且無法復原，是否確定？
            Text("eventsDeleteConfirmMessage")
        }
        .alert("eventsDeleteBatchTitle \(viewModel.selectedCount)", isPresented: $showBatchDeleteConfirmation) {
            // 刪除
            Button("commonDelete", role: .destructive) {
                viewModel.deleteSelectedSessions(using: sessionDataManager)
            }
            // 取消
            Button("commonCancel", role: .cancel) { }
        } message: {
            // 刪除後將同時移除所有類別、商品，且無法復原，是否確定？
            Text("eventsDeleteBatchMessage")
        }
        .sheet(isPresented: $viewModel.showDuplicateSessionDialog) {
            duplicateSessionView
        }
    }

    // MARK: - Segmented Control

    private var segmentedControl: some View {
        Picker("", selection: $displayMode) {
            // 列表
            Text("eventsDisplayList").tag(EventsDisplayMode.list)
            // 日曆
            Text("eventsDisplayCalendar").tag(EventsDisplayMode.calendar)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, DesignSystem.Spacing.md)
        .padding(.vertical, DesignSystem.Spacing.sm)
    }

    // MARK: - List Content

    private var listContent: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                LazyVStack(spacing: 0) {
                    if displayedSessions.isEmpty {
                        emptyStateContent
                    } else {
                        sessionSections
                    }
                }
                .padding(.horizontal, DesignSystem.Spacing.md)
                .padding(.bottom, viewModel.isSelectionMode ? 70 : DesignSystem.Spacing.md)
            }

            if viewModel.isSelectionMode {
                selectionActionBar
            }
        }
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyStateContent: some View {
        if searchText.isEmpty {
            // 尚無場次 / 點擊右上角「+」按鈕新增第一個場次
            EmptyStateView(
                systemImage: "calendar.badge.plus",
                title: String(localized: "eventsEmptyTitle"),
                message: String(localized: "eventsEmptyMessage")
            )
        } else {
            // 查無結果 / 找不到符合「...」的場次
            EmptyStateView(
                systemImage: "magnifyingglass",
                title: String(localized: "eventsSearchEmptyTitle"),
                message: String(localized: "eventsSearchEmptyMessage \(searchText)")
            )
        }
    }

    // MARK: - Session Sections

    private var sessionSections: some View {
        let sections: [(key: String, title: LocalizedStringKey, data: [SessionModel])] = [
            ("today", "eventsSectionToday", ongoingSessions),
            ("upcoming", "eventsSectionUpcoming", upcomingSessions),
            ("past", "eventsSectionPast", completedSessions),
        ].filter { !$0.data.isEmpty }

        return VStack(spacing: 0) {
            ForEach(Array(sections.enumerated()), id: \.element.key) { index, section in
                sessionSection(title: section.title, sessions: section.data, isFirst: index == 0)
            }
        }
    }

    private func sessionSection(title: LocalizedStringKey, sessions: [SessionModel], isFirst: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text(title)
                .font(DesignSystem.Typography.title2)
                .foregroundColor(DesignSystem.ColorToken.ink)
                .padding(.top, isFirst ? DesignSystem.Spacing.md : DesignSystem.Spacing.lg)

            ForEach(sessions) { session in
                HStack(spacing: DesignSystem.Spacing.sm) {
                    if viewModel.isSelectionMode {
                        Image(systemName: viewModel.selectedSessionIds.contains(session.id)
                              ? "checkmark.circle.fill" : "circle")
                            .font(.title2)
                            .foregroundColor(viewModel.selectedSessionIds.contains(session.id)
                                             ? DesignSystem.ColorToken.ink : DesignSystem.ColorToken.muted)
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

    // MARK: - Calendar Placeholder

    private var calendarPlaceholder: some View {
        VStack {
            Spacer()
            Image(systemName: "calendar")
                .font(.system(size: 48))
                .foregroundColor(DesignSystem.ColorToken.muted)
            // 日曆模式（下個斷點實作）
            Text("eventsCalendarPlaceholder")
                .font(DesignSystem.Typography.body)
                .foregroundColor(DesignSystem.ColorToken.muted)
                .padding(.top, DesignSystem.Spacing.sm)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Selection Action Bar

    private var selectionActionBar: some View {
        HStack {
            Button {
                if viewModel.isAllSelected(sessions: displayedSessions) {
                    viewModel.deselectAll()
                } else {
                    viewModel.selectAll(sessions: displayedSessions)
                }
            } label: {
                Text(viewModel.isAllSelected(sessions: displayedSessions)
                     ? String(localized: "eventsDeselectAll") : String(localized: "eventsSelectAll"))
                    .padding(.vertical, DesignSystem.Spacing.xs)
                    .padding(.horizontal, DesignSystem.Spacing.sm)
                    .contentShape(Rectangle())
            }
            .disabled(displayedSessions.isEmpty)

            Spacer()

            Button {
                showBatchDeleteConfirmation = true
            } label: {
                // 刪除 (N)
                Text("eventsDeleteCount \(viewModel.selectedCount)")
                    .foregroundColor(viewModel.isDeleteButtonDisabled
                                     ? DesignSystem.ColorToken.muted : DesignSystem.ColorToken.alertRed)
                    .padding(.vertical, DesignSystem.Spacing.xs)
                    .padding(.horizontal, DesignSystem.Spacing.sm)
                    .contentShape(Rectangle())
            }
            .disabled(viewModel.isDeleteButtonDisabled)
        }
        .padding(.horizontal, DesignSystem.Spacing.sm)
        .padding(.vertical, DesignSystem.Spacing.sm)
        .frame(maxWidth: .infinity)
        .background(DesignSystem.ColorToken.cardSurface)
        .contentShape(Rectangle())
    }

    // MARK: - Session Card

    @ViewBuilder
    private func sessionCard(_ session: SessionModel, showMenu: Bool = true) -> some View {
        if showMenu {
            SessionCardView(
                session: session,
                style: .standard,
                onDuplicate: { viewModel.startDuplicateSession(session) },
                onEdit: { editingSession = session },
                onDelete: {
                    sessionToDelete = session
                    showDeleteConfirmation = true
                }
            )
        } else {
            SessionCardView(session: session, style: .simple)
        }
    }

    // MARK: - Duplicate Session Sheet

    @ViewBuilder
    private var duplicateSessionView: some View {
        NavigationView {
            Form {
                // 場次名稱
                TextField("eventsDuplicateNameLabel", text: $viewModel.duplicateSessionName)
                    .onChange(of: viewModel.duplicateSessionName) {
                        viewModel.onSessionNameChanged()
                    }

                Section {
                    // 場次類型
                    Picker("eventsDuplicateTypeLabel", selection: $viewModel.duplicateSessionDateType) {
                        // 單日
                        Text("eventsDateTypeSingle").tag(SessionDateType.single)
                        // 多日
                        Text("eventsDateTypeMulti").tag(SessionDateType.multi)
                        // 無限期
                        Text("eventsDateTypePermanent").tag(SessionDateType.permanent)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: viewModel.duplicateSessionDateType) { _, newType in
                        if newType == .multi {
                            viewModel.duplicateSessionEndDate = Calendar.current.date(
                                byAdding: .day, value: 1, to: viewModel.duplicateSessionDate
                            ) ?? viewModel.duplicateSessionDate
                        }
                    }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))

                Section {
                    switch viewModel.duplicateSessionDateType {
                    case .single:
                        // 日期
                        DatePicker("eventsDuplicateDate", selection: $viewModel.duplicateSessionDate, displayedComponents: .date)

                    case .multi:
                        // 開始日期
                        DatePicker("eventsDuplicateStartDate", selection: $viewModel.duplicateSessionDate, displayedComponents: .date)
                            .onChange(of: viewModel.duplicateSessionDate) { _, newStartDate in
                                if viewModel.duplicateSessionEndDate <= newStartDate {
                                    viewModel.duplicateSessionEndDate = Calendar.current.date(
                                        byAdding: .day, value: 1, to: newStartDate
                                    ) ?? newStartDate
                                }
                            }

                        // 結束日期
                        DatePicker(
                            "eventsDuplicateEndDate",
                            selection: $viewModel.duplicateSessionEndDate,
                            in: viewModel.duplicateEndDateRange,
                            displayedComponents: .date
                        )

                        HStack {
                            Image(systemName: "info.circle")
                                .foregroundColor(DesignSystem.ColorToken.muted)
                                .font(DesignSystem.Typography.caption)
                            // 多日場次最多 31 天
                            Text("eventsDuplicateMultiDayLimit")
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.ColorToken.muted)
                        }

                    case .permanent:
                        // 開始日期
                        DatePicker("eventsDuplicateStartDate", selection: $viewModel.duplicateSessionDate, displayedComponents: .date)

                        HStack {
                            Image(systemName: "infinity")
                                .foregroundColor(DesignSystem.ColorToken.muted)
                            // 此場次無結束日期
                            Text("eventsDuplicatePermanentHint")
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.ColorToken.muted)
                        }
                    }
                }
            }
            // 複製場次
            .navigationTitle("eventsDuplicateTitle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    // 取消
                    Button("commonCancel") {
                        viewModel.cancelDuplicateSession()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    // 確定
                    Button("commonConfirm") {
                        viewModel.confirmDuplicateSession(using: sessionDataManager)
                    }
                    .disabled(viewModel.isDuplicateButtonDisabled)
                }
            }
        }
        .presentationDetents([.fraction(0.55)])
    }
}
