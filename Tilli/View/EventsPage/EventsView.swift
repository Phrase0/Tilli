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

    @EnvironmentObject var eventDataManager: EventRepository
    @EnvironmentObject var transactionDataManager: TransactionRepository
    @StateObject private var eventsVM = EventsViewModel()
    @StateObject private var calendarVM = EventsCalendarViewModel()

    @State private var searchText = ""
    @State private var isSearching = false
    @State private var showAddEventSheet = false
    @State private var editingEvent: EventModel? = nil
    @State private var eventToDelete: EventModel? = nil
    @State private var showDeleteConfirmation = false
    @State private var showBatchDeleteConfirmation = false
    @State private var selectedEvent: EventModel? = nil

    private var displayedEvents: [EventModel] {
        eventsVM.sortedFilteredEvents(by: searchText, from: eventDataManager.events)
    }

    private var ongoingEvents: [EventModel] {
        displayedEvents.filter { $0.status == .ongoing }
    }

    private var upcomingEvents: [EventModel] {
        displayedEvents.filter { $0.status == .upcoming }
    }

    private var completedEvents: [EventModel] {
        displayedEvents.filter { $0.status == .completed }
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
                        onSelectEvent: { event in
                            selectedEvent = event
                        },
                        onDuplicate: { event in
                            eventsVM.startDuplicateEvent(event)
                        },
                        onEdit: { event in
                            editingEvent = event
                        },
                        onDelete: { event in
                            eventToDelete = event
                            showDeleteConfirmation = true
                        }
                    )
                }
            }
            .background(DesignSystem.ColorToken.paper)
            .navigationTitle("eventsPageTitle")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if eventsVM.isSelectionMode {
                        Button("commonCancel") {
                            eventsVM.exitSelectionMode()
                        }
                    }
                }

                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    if eventsVM.isSelectionMode {
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
                            showAddEventSheet = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .navigationDestination(item: $selectedEvent) { event in
                WorkspaceView(event: event)
            }
            .toolbar(eventsVM.isSelectionMode ? .hidden : .visible, for: .tabBar)
            .animation(.easeInOut(duration: 0.3), value: eventsVM.isSelectionMode)
        }
        .onAppear {
            eventsVM.updateDataManagers(transactionDataManager: transactionDataManager)
            calendarVM.updateDataManagers(
                transactionDataManager: transactionDataManager,
                eventDataManager: eventDataManager
            )
        }
        .sheet(isPresented: $showAddEventSheet) {
            NavigationStack {
                AddEventView(onSave: { newEvent in
                    eventsVM.addEvent(newEvent, using: eventDataManager)
                    showAddEventSheet = false
                })
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $editingEvent) { event in
            NavigationStack {
                AddEventView(eventToEdit: event, onSave: { updateEvent in
                    eventsVM.updateEvent(updateEvent, using: eventDataManager)
                    editingEvent = nil
                })
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .alert("eventsDeleteConfirmTitle", isPresented: $showDeleteConfirmation, presenting: eventToDelete) { event in
            Button("commonDelete", role: .destructive) {
                eventsVM.deleteEvent(event, using: eventDataManager)
            }
            Button("commonCancel", role: .cancel) { }
        } message: { _ in
            Text("eventsDeleteConfirmMessage")
        }
        .alert("eventsDeleteBatchTitle \(eventsVM.selectedCount)", isPresented: $showBatchDeleteConfirmation) {
            Button("commonDelete", role: .destructive) {
                eventsVM.deleteSelectedEvents(using: eventDataManager)
            }
            Button("commonCancel", role: .cancel) { }
        } message: {
            Text("eventsDeleteBatchMessage")
        }
        .sheet(isPresented: $eventsVM.showDuplicateEventDialog) {
            duplicateEventView
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
                    if displayedEvents.isEmpty {
                        emptyStateContent
                    } else {
                        eventSections
                    }
                }
                .padding(.horizontal, DesignSystem.Spacing.md)
                .padding(.bottom, eventsVM.isSelectionMode ? 70 : DesignSystem.Spacing.md)
            }

            if eventsVM.isSelectionMode {
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

    // MARK: - Event Sections

    private var eventSections: some View {
        let sections: [(key: String, title: LocalizedStringKey, data: [EventModel])] = [
            ("today", "eventsSectionToday", ongoingEvents),
            ("upcoming", "eventsSectionUpcoming", upcomingEvents),
            ("past", "eventsSectionPast", completedEvents),
        ].filter { !$0.data.isEmpty }

        return VStack(spacing: 0) {
            ForEach(Array(sections.enumerated()), id: \.element.key) { index, section in
                eventSection(title: section.title, events: section.data, isFirst: index == 0)
            }
        }
    }

    private func eventSection(title: LocalizedStringKey, events: [EventModel], isFirst: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text(title)
                .font(DesignSystem.Typography.title2)
                .foregroundColor(DesignSystem.ColorToken.ink)
                .padding(.top, isFirst ? DesignSystem.Spacing.md : DesignSystem.Spacing.lg)

            ForEach(events) { event in
                HStack(spacing: DesignSystem.Spacing.sm) {
                    if eventsVM.isSelectionMode {
                        Image(systemName: eventsVM.selectedEventIds.contains(event.id)
                              ? "checkmark.circle.fill" : "circle")
                            .font(.title2)
                            .foregroundColor(eventsVM.selectedEventIds.contains(event.id)
                                             ? DesignSystem.ColorToken.ink : DesignSystem.ColorToken.muted)
                    }

                    eventCard(event, style: eventsVM.isSelectionMode ? .simple : .standard)
                }
                .onTapGesture {
                    if eventsVM.isSelectionMode {
                        eventsVM.toggleSelection(eventId: event.id)
                    } else {
                        selectedEvent = event
                    }
                }
                .onLongPressGesture {
                    if !eventsVM.isSelectionMode {
                        eventsVM.enterSelectionMode()
                        eventsVM.toggleSelection(eventId: event.id)
                    }
                }
            }
        }
    }

    // MARK: - Selection Action Bar

    private var selectionActionBar: some View {
        HStack {
            Button {
                if eventsVM.isAllSelected(events: displayedEvents) {
                    eventsVM.deselectAll()
                } else {
                    eventsVM.selectAll(events: displayedEvents)
                }
            } label: {
                Text(eventsVM.isAllSelected(events: displayedEvents)
                     ? String(localized: "eventsDeselectAll") : String(localized: "eventsSelectAll"))
                    .padding(.vertical, DesignSystem.Spacing.xs)
                    .padding(.horizontal, DesignSystem.Spacing.sm)
                    .contentShape(Rectangle())
            }
            .disabled(displayedEvents.isEmpty)

            Spacer()

            Button {
                showBatchDeleteConfirmation = true
            } label: {
                Text("eventsDeleteCount \(eventsVM.selectedCount)")
                    .foregroundColor(eventsVM.isDeleteButtonDisabled
                                     ? DesignSystem.ColorToken.muted : DesignSystem.ColorToken.alertRed)
                    .padding(.vertical, DesignSystem.Spacing.xs)
                    .padding(.horizontal, DesignSystem.Spacing.sm)
                    .contentShape(Rectangle())
            }
            .disabled(eventsVM.isDeleteButtonDisabled)
        }
        .padding(.horizontal, DesignSystem.Spacing.sm)
        .padding(.vertical, DesignSystem.Spacing.sm)
        .frame(maxWidth: .infinity)
        .background(DesignSystem.ColorToken.cardSurface)
        .contentShape(Rectangle())
    }

    // MARK: - Event Card

    @ViewBuilder
    private func eventCard(_ event: EventModel, style: EventCardStyle) -> some View {
        let summary = eventsVM.transactionSummary(for: event)
        switch style {
        case .standard:
            EventCardView(
                event: event,
                style: .standard,
                transactionCount: summary.count,
                transactionTotal: summary.total,
                onDuplicate: { eventsVM.startDuplicateEvent(event) },
                onEdit: { editingEvent = event },
                onDelete: {
                    eventToDelete = event
                    showDeleteConfirmation = true
                }
            )
        case .simple:
            EventCardView(
                event: event,
                style: .simple,
                transactionCount: summary.count,
                transactionTotal: summary.total
            )
        }
    }

    // MARK: - Duplicate Event Sheet

    @ViewBuilder
    private var duplicateEventView: some View {
        NavigationView {
            Form {
                TextField("eventsDuplicateNameLabel", text: $eventsVM.duplicateEventName)
                    .onChange(of: eventsVM.duplicateEventName) {
                        eventsVM.onEventNameChanged()
                    }

                Section {
                    Picker("eventsDuplicateTypeLabel", selection: $eventsVM.duplicateEventDateType) {
                        Text("eventsDateTypeSingle").tag(EventDateType.single)
                        Text("eventsDateTypeMulti").tag(EventDateType.multi)
                        Text("eventsDateTypePermanent").tag(EventDateType.permanent)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: eventsVM.duplicateEventDateType) { _, newType in
                        if newType == .multi {
                            eventsVM.duplicateEventEndDate = Calendar.current.date(
                                byAdding: .day, value: 1, to: eventsVM.duplicateEventDate
                            ) ?? eventsVM.duplicateEventDate
                        }
                    }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))

                Section {
                    switch eventsVM.duplicateEventDateType {
                    case .single:
                        DatePicker("eventsDuplicateDate", selection: $eventsVM.duplicateEventDate, displayedComponents: .date)

                    case .multi:
                        DatePicker("eventsDuplicateStartDate", selection: $eventsVM.duplicateEventDate, displayedComponents: .date)
                            .onChange(of: eventsVM.duplicateEventDate) { _, newStartDate in
                                if eventsVM.duplicateEventEndDate <= newStartDate {
                                    eventsVM.duplicateEventEndDate = Calendar.current.date(
                                        byAdding: .day, value: 1, to: newStartDate
                                    ) ?? newStartDate
                                }
                            }

                        DatePicker(
                            "eventsDuplicateEndDate",
                            selection: $eventsVM.duplicateEventEndDate,
                            in: eventsVM.duplicateEndDateRange,
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
                        DatePicker("eventsDuplicateStartDate", selection: $eventsVM.duplicateEventDate, displayedComponents: .date)

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
                        eventsVM.cancelDuplicateEvent()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("commonConfirm") {
                        eventsVM.confirmDuplicateEvent(using: eventDataManager)
                    }
                    .disabled(eventsVM.isDuplicateButtonDisabled)
                }
            }
        }
        .presentationDetents([.fraction(0.55)])
    }
}
