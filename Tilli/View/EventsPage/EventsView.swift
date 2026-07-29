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
    @EnvironmentObject var transactionDataManager: TransactionRepository
    @StateObject private var eventsVM = EventsViewModel()
    @StateObject private var sessionVM = SessionViewModel()
    @StateObject private var calendarVM = EventsCalendarViewModel()

    @State private var searchText = ""
    @State private var isSearching = false
    @State private var showAddSessionSheet = false
    @State private var editingSession: SessionModel? = nil
    @State private var sessionToDelete: SessionModel? = nil
    @State private var showDeleteConfirmation = false
    @State private var showBatchDeleteConfirmation = false
    @State private var selectedSession: SessionModel? = nil

    private var displayedSessions: [SessionModel] {
        sessionVM.sortedFilteredSessions(by: searchText, from: sessionDataManager.sessions)
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
                if isSearching {
                    searchBar
                }

                segmentedControl

                switch eventsVM.displayMode {
                case .list:
                    listContent
                case .calendar:
                    EventsCalendarView(
                        calendarVM: calendarVM,
                        onSelectSession: { session in
                            selectedSession = session
                        }
                    )
                }
            }
            .background(DesignSystem.ColorToken.paper)
            .navigationTitle("eventsPageTitle")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if sessionVM.isSelectionMode {
                        Button("commonCancel") {
                            sessionVM.exitSelectionMode()
                        }
                    }
                }

                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    if sessionVM.isSelectionMode {
                        EmptyView()
                    } else {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isSearching.toggle()
                            }
                            if !isSearching { searchText = "" }
                        } label: {
                            Image(systemName: "magnifyingglass")
                        }

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
            .toolbar(sessionVM.isSelectionMode ? .hidden : .visible, for: .tabBar)
            .animation(.easeInOut(duration: 0.3), value: sessionVM.isSelectionMode)
        }
        .onAppear {
            eventsVM.updateDataManagers(transactionDataManager: transactionDataManager)
            calendarVM.updateDataManagers(
                transactionDataManager: transactionDataManager,
                sessionDataManager: sessionDataManager
            )
        }
        .sheet(isPresented: $showAddSessionSheet) {
            NavigationStack {
                AddSessionView(onSave: { newSession in
                    sessionVM.addSession(newSession, using: sessionDataManager)
                    showAddSessionSheet = false
                })
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $editingSession) { session in
            NavigationStack {
                AddSessionView(sessionToEdit: session, onSave: { updatedSession in
                    sessionVM.updateSession(updatedSession, using: sessionDataManager)
                    editingSession = nil
                })
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .alert("eventsDeleteConfirmTitle", isPresented: $showDeleteConfirmation, presenting: sessionToDelete) { session in
            Button("commonDelete", role: .destructive) {
                sessionVM.deleteSession(session, using: sessionDataManager)
            }
            Button("commonCancel", role: .cancel) { }
        } message: { _ in
            Text("eventsDeleteConfirmMessage")
        }
        .alert("eventsDeleteBatchTitle \(sessionVM.selectedCount)", isPresented: $showBatchDeleteConfirmation) {
            Button("commonDelete", role: .destructive) {
                sessionVM.deleteSelectedSessions(using: sessionDataManager)
            }
            Button("commonCancel", role: .cancel) { }
        } message: {
            Text("eventsDeleteBatchMessage")
        }
        .sheet(isPresented: $sessionVM.showDuplicateSessionDialog) {
            duplicateSessionView
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: DesignSystem.Spacing.xs) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(DesignSystem.ColorToken.muted)

            TextField(String(localized: "eventsSearchPrompt"), text: $searchText)
                .font(DesignSystem.Typography.body)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(DesignSystem.ColorToken.muted)
                }
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.sm)
        .padding(.vertical, DesignSystem.Spacing.xs)
        .background(DesignSystem.ColorToken.quietFill)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.sm))
        .padding(.horizontal, DesignSystem.Spacing.md)
        .padding(.top, DesignSystem.Spacing.xs)
    }

    // MARK: - Segmented Control

    private var segmentedControl: some View {
        Picker("", selection: $eventsVM.displayMode) {
            Text("eventsDisplayList").tag(EventsDisplayMode.list)
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
                .padding(.bottom, sessionVM.isSelectionMode ? 70 : DesignSystem.Spacing.md)
            }

            if sessionVM.isSelectionMode {
                selectionActionBar
            }
        }
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyStateContent: some View {
        if searchText.isEmpty {
            EmptyStateView(
                systemImage: "calendar.badge.plus",
                title: String(localized: "eventsEmptyTitle"),
                message: String(localized: "eventsEmptyMessage")
            )
        } else {
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
                    if sessionVM.isSelectionMode {
                        Image(systemName: sessionVM.selectedSessionIds.contains(session.id)
                              ? "checkmark.circle.fill" : "circle")
                            .font(.title2)
                            .foregroundColor(sessionVM.selectedSessionIds.contains(session.id)
                                             ? DesignSystem.ColorToken.ink : DesignSystem.ColorToken.muted)
                    }

                    sessionCard(session, style: sessionVM.isSelectionMode ? .simple : .standard)
                }
                .onTapGesture {
                    if sessionVM.isSelectionMode {
                        sessionVM.toggleSelection(sessionId: session.id)
                    } else {
                        selectedSession = session
                    }
                }
                .onLongPressGesture {
                    if !sessionVM.isSelectionMode {
                        sessionVM.enterSelectionMode()
                        sessionVM.toggleSelection(sessionId: session.id)
                    }
                }
            }
        }
    }

    // MARK: - Selection Action Bar

    private var selectionActionBar: some View {
        HStack {
            Button {
                if sessionVM.isAllSelected(sessions: displayedSessions) {
                    sessionVM.deselectAll()
                } else {
                    sessionVM.selectAll(sessions: displayedSessions)
                }
            } label: {
                Text(sessionVM.isAllSelected(sessions: displayedSessions)
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
                Text("eventsDeleteCount \(sessionVM.selectedCount)")
                    .foregroundColor(sessionVM.isDeleteButtonDisabled
                                     ? DesignSystem.ColorToken.muted : DesignSystem.ColorToken.alertRed)
                    .padding(.vertical, DesignSystem.Spacing.xs)
                    .padding(.horizontal, DesignSystem.Spacing.sm)
                    .contentShape(Rectangle())
            }
            .disabled(sessionVM.isDeleteButtonDisabled)
        }
        .padding(.horizontal, DesignSystem.Spacing.sm)
        .padding(.vertical, DesignSystem.Spacing.sm)
        .frame(maxWidth: .infinity)
        .background(DesignSystem.ColorToken.cardSurface)
        .contentShape(Rectangle())
    }

    // MARK: - Session Card

    @ViewBuilder
    private func sessionCard(_ session: SessionModel, style: SessionCardStyle) -> some View {
        let summary = eventsVM.transactionSummary(for: session)
        switch style {
        case .standard:
            SessionCardView(
                session: session,
                style: .standard,
                transactionCount: summary.count,
                transactionTotal: summary.total,
                onDuplicate: { sessionVM.startDuplicateSession(session) },
                onEdit: { editingSession = session },
                onDelete: {
                    sessionToDelete = session
                    showDeleteConfirmation = true
                }
            )
        case .simple:
            SessionCardView(
                session: session,
                style: .simple,
                transactionCount: summary.count,
                transactionTotal: summary.total
            )
        }
    }

    // MARK: - Duplicate Session Sheet

    @ViewBuilder
    private var duplicateSessionView: some View {
        NavigationView {
            Form {
                TextField("eventsDuplicateNameLabel", text: $sessionVM.duplicateSessionName)
                    .onChange(of: sessionVM.duplicateSessionName) {
                        sessionVM.onSessionNameChanged()
                    }

                Section {
                    Picker("eventsDuplicateTypeLabel", selection: $sessionVM.duplicateSessionDateType) {
                        Text("eventsDateTypeSingle").tag(SessionDateType.single)
                        Text("eventsDateTypeMulti").tag(SessionDateType.multi)
                        Text("eventsDateTypePermanent").tag(SessionDateType.permanent)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: sessionVM.duplicateSessionDateType) { _, newType in
                        if newType == .multi {
                            sessionVM.duplicateSessionEndDate = Calendar.current.date(
                                byAdding: .day, value: 1, to: sessionVM.duplicateSessionDate
                            ) ?? sessionVM.duplicateSessionDate
                        }
                    }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))

                Section {
                    switch sessionVM.duplicateSessionDateType {
                    case .single:
                        DatePicker("eventsDuplicateDate", selection: $sessionVM.duplicateSessionDate, displayedComponents: .date)

                    case .multi:
                        DatePicker("eventsDuplicateStartDate", selection: $sessionVM.duplicateSessionDate, displayedComponents: .date)
                            .onChange(of: sessionVM.duplicateSessionDate) { _, newStartDate in
                                if sessionVM.duplicateSessionEndDate <= newStartDate {
                                    sessionVM.duplicateSessionEndDate = Calendar.current.date(
                                        byAdding: .day, value: 1, to: newStartDate
                                    ) ?? newStartDate
                                }
                            }

                        DatePicker(
                            "eventsDuplicateEndDate",
                            selection: $sessionVM.duplicateSessionEndDate,
                            in: sessionVM.duplicateEndDateRange,
                            displayedComponents: .date
                        )

                        HStack {
                            Image(systemName: "info.circle")
                                .foregroundColor(DesignSystem.ColorToken.muted)
                                .font(DesignSystem.Typography.caption)
                            Text("eventsDuplicateMultiDayLimit")
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.ColorToken.muted)
                        }

                    case .permanent:
                        DatePicker("eventsDuplicateStartDate", selection: $sessionVM.duplicateSessionDate, displayedComponents: .date)

                        HStack {
                            Image(systemName: "infinity")
                                .foregroundColor(DesignSystem.ColorToken.muted)
                            Text("eventsDuplicatePermanentHint")
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.ColorToken.muted)
                        }
                    }
                }
            }
            .navigationTitle("eventsDuplicateTitle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("commonCancel") {
                        sessionVM.cancelDuplicateSession()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("commonConfirm") {
                        sessionVM.confirmDuplicateSession(using: sessionDataManager)
                    }
                    .disabled(sessionVM.isDuplicateButtonDisabled)
                }
            }
        }
        .presentationDetents([.fraction(0.55)])
    }
}
