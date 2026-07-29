//
//  EventsCalendarView.swift
//  Tilli
//
//  Created by Peiyun on 2026/7/29.
//

import SwiftUI

struct EventsCalendarView: View {

    @ObservedObject var eventsVM: EventsViewModel
    @EnvironmentObject var sessionDataManager: SessionRepository
    var onSelectSession: (SessionModel) -> Void

    private let calendar = Calendar.current

    var body: some View {
        VStack(spacing: 0) {
            monthHeader
            weekHeader
            calendarGrid
            calendarSessionList
            Spacer()
        }
        .onAppear {
            eventsVM.selectedDate = Date()
        }
    }

    // MARK: - Month Header

    private var monthHeader: some View {
        HStack(spacing: 0) {
            Button {
                eventsVM.changeMonth(-1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(DesignSystem.ColorToken.muted)
                    .frame(width: 44, height: 44)
            }

            Spacer()

            Button {
                eventsVM.showingMonthYearPicker = true
            } label: {
                Text(eventsVM.monthYearString())
                    .font(DesignSystem.Typography.title2)
                    .foregroundColor(DesignSystem.ColorToken.ink)
            }
            .sheet(isPresented: $eventsVM.showingMonthYearPicker) {
                CalendarMonthYearPicker(
                    currentDate: $eventsVM.currentDate,
                    isPresented: $eventsVM.showingMonthYearPicker
                )
            }

            Spacer()

            Button {
                eventsVM.changeMonth(1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(DesignSystem.ColorToken.muted)
                    .frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .padding(.vertical, DesignSystem.Spacing.sm)
    }

    // MARK: - Week Header

    private var weekHeader: some View {
        HStack {
            ForEach(eventsVM.weekdays, id: \.self) { day in
                Text(day)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.ColorToken.muted)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .padding(.bottom, DesignSystem.Spacing.xs)
    }

    // MARK: - Calendar Grid

    private var calendarGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 0) {
            ForEach(eventsVM.daysInMonth(), id: \.self) { date in
                let sessionsForDate = eventsVM.sessionsForDate(date, from: sessionDataManager.sessions)
                let hasTransactions = eventsVM.hasTransactions(on: date)

                CalendarDayCell(
                    date: date,
                    isSelected: calendar.isDate(date, inSameDayAs: eventsVM.selectedDate),
                    isToday: calendar.isDateInToday(date),
                    sessions: sessionsForDate,
                    hasOrphanTransactions: hasTransactions && sessionsForDate.isEmpty,
                    currentMonth: eventsVM.currentDate,
                    onTap: { eventsVM.selectedDate = date }
                )
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .gesture(
            DragGesture()
                .onEnded { value in
                    if value.translation.width > 50 {
                        eventsVM.changeMonth(-1)
                    } else if value.translation.width < -50 {
                        eventsVM.changeMonth(1)
                    }
                }
        )
    }

    // MARK: - Session List

    private var calendarSessionList: some View {
        let (realSessions, virtualSessions) = eventsVM.getAllSessionsForDate(from: sessionDataManager.sessions)
        let permanentSessions = eventsVM.getPermanentSessions(from: sessionDataManager.sessions)

        return Group {
            if !realSessions.isEmpty || !virtualSessions.isEmpty || !permanentSessions.isEmpty {
                ScrollView {
                    LazyVStack(spacing: DesignSystem.Spacing.sm) {
                        if !permanentSessions.isEmpty {
                            ForEach(permanentSessions) { session in
                                CalendarSessionRow(
                                    session: session,
                                    isVirtual: false,
                                    isPermanent: true,
                                    progressInfo: eventsVM.sessionProgressInfo(for: session),
                                    summary: eventsVM.calculateTransactionSummary(for: session)
                                )
                                .onTapGesture { onSelectSession(session) }
                            }
                        }

                        ForEach(realSessions) { session in
                            CalendarSessionRow(
                                session: session,
                                isVirtual: false,
                                isPermanent: false,
                                progressInfo: eventsVM.sessionProgressInfo(for: session),
                                summary: eventsVM.calculateTransactionSummary(for: session)
                            )
                            .onTapGesture { onSelectSession(session) }
                        }

                        ForEach(virtualSessions) { session in
                            CalendarSessionRow(
                                session: session,
                                isVirtual: true,
                                isPermanent: false,
                                progressInfo: nil,
                                summary: eventsVM.calculateTransactionSummary(for: session)
                            )
                            .opacity(0.7)
                            .onTapGesture { onSelectSession(session) }
                        }
                    }
                    .padding(.horizontal, DesignSystem.Spacing.md)
                    .padding(.top, DesignSystem.Spacing.md)
                }
            }
        }
    }
}

// MARK: - Day Cell

struct CalendarDayCell: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let sessions: [SessionModel]
    let hasOrphanTransactions: Bool
    let currentMonth: Date
    let onTap: () -> Void

    private let calendar = Calendar.current

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                ZStack {
                    if isSelected {
                        Circle()
                            .fill(DesignSystem.ColorToken.ink)
                            .frame(width: 30, height: 30)
                    }

                    Text("\(calendar.component(.day, from: date))")
                        .font(.system(size: 16, weight: isToday ? .bold : .medium))
                        .foregroundColor(textColor)
                }

                sessionIndicators
            }
            .frame(height: 44)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var sessionIndicators: some View {
        Group {
            if !sessions.isEmpty {
                HStack(spacing: 2) {
                    ForEach(sessions.prefix(3)) { session in
                        Circle()
                            .fill(session.status == .ongoing
                                  ? DesignSystem.ColorToken.marketGreen
                                  : DesignSystem.ColorToken.muted)
                            .frame(width: 4, height: 4)
                    }

                    if sessions.count > 3 {
                        Text("+\(sessions.count - 3)")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(DesignSystem.ColorToken.muted)
                    }
                }
                .frame(height: 8)
            } else if hasOrphanTransactions {
                Circle()
                    .fill(DesignSystem.ColorToken.muted.opacity(0.5))
                    .frame(width: 4, height: 4)
                    .frame(height: 8)
            } else {
                Spacer().frame(height: 8)
            }
        }
    }

    private var textColor: Color {
        if isSelected {
            return DesignSystem.ColorToken.cardSurface
        } else if !calendar.isDate(date, equalTo: currentMonth, toGranularity: .month) {
            return DesignSystem.ColorToken.muted.opacity(0.4)
        } else {
            return DesignSystem.ColorToken.ink
        }
    }
}

// MARK: - Calendar Session Row

struct CalendarSessionRow: View {
    let session: SessionModel
    let isVirtual: Bool
    let isPermanent: Bool
    let progressInfo: String?
    let summary: (count: Int, totalAmount: Decimal)

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: DesignSystem.Spacing.xs) {
                    Text(session.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(DesignSystem.ColorToken.ink)
                        .lineLimit(1)

                    if isPermanent {
                        Text("∞")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.ColorToken.muted)
                    }
                }

                if let info = progressInfo {
                    Text(info)
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.ColorToken.muted)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(summary.totalAmount.money(currency: session.currency))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(DesignSystem.ColorToken.ink)

                // N 筆交易
                Text("calendarTransactionCount \(summary.count)")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.ColorToken.muted)
            }
        }
        .padding(DesignSystem.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isVirtual ? DesignSystem.ColorToken.quietFill : DesignSystem.ColorToken.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.md))
        .shadow(
            color: DesignSystem.Shadow.cardColor,
            radius: DesignSystem.Shadow.cardRadius,
            x: DesignSystem.Shadow.cardX,
            y: DesignSystem.Shadow.cardY
        )
    }
}

// MARK: - Month/Year Picker

struct CalendarMonthYearPicker: View {
    @Binding var currentDate: Date
    @Binding var isPresented: Bool
    @State private var selectedYear: Int
    @State private var selectedMonth: Int

    private let calendar = Calendar.current
    private let years = Array(2020...2080)
    private let months = Array(1...12)

    init(currentDate: Binding<Date>, isPresented: Binding<Bool>) {
        self._currentDate = currentDate
        self._isPresented = isPresented
        let year = Calendar.current.component(.year, from: currentDate.wrappedValue)
        let month = Calendar.current.component(.month, from: currentDate.wrappedValue)
        self._selectedYear = State(initialValue: year)
        self._selectedMonth = State(initialValue: month)
    }

    var body: some View {
        NavigationView {
            HStack {
                // 年份
                Picker("calendarPickerYear", selection: $selectedYear) {
                    ForEach(years, id: \.self) { year in
                        // %d年
                        Text("calendarYearSuffix \(year)").tag(year)
                    }
                }
                .pickerStyle(WheelPickerStyle())

                // 月份
                Picker("calendarPickerMonth", selection: $selectedMonth) {
                    ForEach(months, id: \.self) { month in
                        // %d月
                        Text("calendarMonthSuffix \(month)").tag(month)
                    }
                }
                .pickerStyle(WheelPickerStyle())
            }
            // 選擇月份
            .navigationTitle("calendarPickerTitle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    // 取消
                    Button("commonCancel") {
                        isPresented = false
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    // 確定
                    Button("commonConfirm") {
                        updateDate()
                        isPresented = false
                    }
                }
            }
        }
        .presentationDetents([.fraction(0.45)])
    }

    private func updateDate() {
        let components = DateComponents(year: selectedYear, month: selectedMonth, day: 1)
        if let newDate = calendar.date(from: components) {
            currentDate = newDate
        }
    }
}
