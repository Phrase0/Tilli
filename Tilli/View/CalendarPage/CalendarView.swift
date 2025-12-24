//
//  CalendarView.swift
//  Tilli
//
//  Created by Peiyun on 2025/4/22.
//

import SwiftUI
import Foundation

struct CalendarView: View {
    @EnvironmentObject var sessionDataManager: SessionDataManager
    @EnvironmentObject var transactionDataManager: TransactionDataManager
    @StateObject private var viewModel = CalendarViewModel()
    @State private var currentDate = Date()
    @State private var selectedDate = Date()
    @State private var showingMonthYearPicker = false
    @State private var refreshID = UUID()

    private let calendar = Calendar.current
    
    var body: some View {
        NavigationStack{
            VStack(spacing: 0) {
                // 月份標題和導航
                monthHeader
                
                // 星期標頭
                weekHeader
                
                // 日曆格子
                calendarGrid
                
                // 選中日期的 Session 列表
                sessionList
                    .id(refreshID)

                Spacer()
            }
            .onAppear {
                viewModel.updateDataManagers(
                    transactionDataManager: transactionDataManager,
                    sessionDataManager: sessionDataManager
                )
                // 設置完 dataManagers 後刷新，確保首次載入資料正確
                refreshID = UUID()
            }
            .onChange(of: transactionDataManager.transactionUpdateTrigger) {
                // 交易變更時刷新 sessionList
                refreshID = UUID()
            }
            .navigationTitle("我的行事曆")
        }
        
    }
    
    // 月份標題
    private var monthHeader: some View {
        HStack(spacing: 0) {
            Button(action: { viewModel.changeMonth(-1, currentDate: &currentDate) }) {
                Image(systemName: "chevron.left")
                    .font(.title3)
                    .foregroundColor(.gray)
                    .frame(width: 44, height: 44)
            }

            Spacer()

            Button(action: { showingMonthYearPicker = true }) {
                Text(viewModel.monthYearString(for: currentDate))
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.black)
            }
            .sheet(isPresented: $showingMonthYearPicker) {
                MonthYearPickerView(
                    currentDate: $currentDate,
                    isPresented: $showingMonthYearPicker
                )
            }

            Spacer()

            Button(action: { viewModel.changeMonth(1, currentDate: &currentDate) }) {
                Image(systemName: "chevron.right")
                    .font(.title3)
                    .foregroundColor(.gray)
                    .frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 12)
    }

    // 星期標頭
    private var weekHeader: some View {
        HStack {
            ForEach(viewModel.weekdays, id: \.self) { day in
                Text(day)
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 30)
        .padding(.bottom, 8)
    }
    
    // 日曆格子
    private var calendarGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 0) {
            ForEach(viewModel.daysInMonth(for: currentDate), id: \.self) { date in
                let sessionsForDate = viewModel.sessionsForDate(date, from: sessionDataManager.sessions)
                let hasTransactions = viewModel.hasTransactions(on: date)

                DayCell(
                    date: date,
                    isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
                    isToday: calendar.isDateInToday(date),
                    sessions: sessionsForDate,
                    hasOrphanTransactions: hasTransactions && sessionsForDate.isEmpty,
                    currentMonth: currentDate,
                    onTap: { selectedDate = date }
                )
            }
        }
        .padding(.horizontal, 30)
        .gesture(
            DragGesture()
                .onEnded { value in
                    if value.translation.width > 50 {
                        viewModel.changeMonth(-1, currentDate: &currentDate)
                    } else if value.translation.width < -50 {
                        viewModel.changeMonth(1, currentDate: &currentDate)
                    }
                }
        )
    }
    
    // Session 列表
    private var sessionList: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 1. 獲取選中日期的場次（不包含永久場次）
            let (realSessions, virtualSessions) = viewModel.getAllSessionsForDate(selectedDate, from: sessionDataManager.sessions)

            // 2. 獲取所有永久場次（固定顯示，需判斷 startDate <= selectedDate）
            let permanentSessions = viewModel.getPermanentSessions(from: sessionDataManager.sessions, selectedDate: selectedDate)

            if !realSessions.isEmpty || !virtualSessions.isEmpty || !permanentSessions.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        // 永久場次（固定顯示，紫色底 + ∞ 符號）
                        if !permanentSessions.isEmpty {
                            ForEach(permanentSessions) { session in
                                NavigationLink(destination: SessionDetailFromCalendarView(
                                    session: .constant(session)
                                )) {
                                    SessionRowView(session: session, isVirtual: false, isPermanent: true, selectedDate: selectedDate, viewModel: viewModel)
                                }
                            }

                            // 永久場次和當日場次之間的分隔線
                            if !realSessions.isEmpty || !virtualSessions.isEmpty {
                                Divider()
                                    .padding(.vertical, 8)
                            }
                        }

                        // 選中日期的真實 Session（藍色底）
                        ForEach(realSessions) { session in
                            NavigationLink(destination: SessionDetailFromCalendarView(
                                session: .constant(session)
                            )) {
                                SessionRowView(session: session, isVirtual: false, isPermanent: false, selectedDate: selectedDate, viewModel: viewModel)
                            }
                        }

                        // 選中日期的虛擬 Session（孤兒交易，灰色底 + 淡化）
                        ForEach(virtualSessions) { session in
                            NavigationLink(destination: SessionDetailFromCalendarView(
                                session: .constant(session)
                            )) {
                                SessionRowView(session: session, isVirtual: true, isPermanent: false, selectedDate: selectedDate, viewModel: viewModel)
                                    .opacity(0.7)  // 淡化顯示
                            }
                        }
                    }
                    .padding(.horizontal, 30)
                    .padding(.top, 20)
                }
            }
        }
    }
}

// 日期單元格
struct DayCell: View {
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
                            .fill(Color.blue)
                            .frame(width: 30, height: 30)
                    }

                    Text("\(calendar.component(.day, from: date))")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(textColor)
                }

                // 場次指示器
                sessionIndicators
            }
            .frame(height: 44)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PlainButtonStyle())
    }

    // 場次指示器：顯示多個圓點或文字
    private var sessionIndicators: some View {
        Group {
            if !sessions.isEmpty {
                HStack(spacing: 2) {
                    // 顯示最多 3 個圓點
                    ForEach(sessions.prefix(3)) { session in
                        Circle()
                            .fill(dotColor(for: session))
                            .frame(width: 4, height: 4)
                    }

                    // 如果超過 3 個場次，顯示 "+X"
                    if sessions.count > 3 {
                        Text("+\(sessions.count - 3)")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.blue)
                    }
                }
                .frame(height: 8)
            } else if hasOrphanTransactions {
                // 孤兒交易：灰色圓點
                Circle()
                    .fill(Color.gray.opacity(0.5))
                    .frame(width: 4, height: 4)
                    .frame(height: 8)
            } else {
                Spacer().frame(height: 8)
            }
        }
    }

    // 根據場次類型返回圓點顏色
    private func dotColor(for session: SessionModel) -> Color {
        switch session.dateType {
        case .permanent:
            return .purple  // 無限期場次用紫色
        case .single, .multi:
            return .blue    // 單日和多日場次用藍色
        }
    }

    private var textColor: Color {
        if isSelected {
            return .white
        } else if isToday {
            return .blue
        } else if !calendar.isDate(date, equalTo: currentMonth, toGranularity: .month) {
            return .gray.opacity(0.4)
        } else {
            return .black
        }
    }
}


// Session 行視圖
struct SessionRowView: View {
    let session: SessionModel
    let isVirtual: Bool      // 是否為虛擬 Session（孤兒交易）
    let isPermanent: Bool    // 是否為永久場次
    let selectedDate: Date   // 日曆選中的日期
    let viewModel: CalendarViewModel

    var body: some View {
        HStack(alignment: .top) {
            // 左側：標題 + 場次資訊
            VStack(alignment: .leading, spacing: 4) {
                Text(session.title + (isPermanent ? " ∞" : ""))
                    .font(.headline)
                    .foregroundColor(.black)

                // 場次進度資訊
                if let sessionInfo = sessionProgressInfo {
                    Text(sessionInfo)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // 右側：金額 + 交易筆數
            VStack(alignment: .trailing, spacing: 6) {
                Text(viewModel.totalAmount(for: session).money(currency: session.currency))
                    .font(.headline)
                    .foregroundColor(isPermanent ? .purple : .blue)

                Text("\(viewModel.getTransactionCount(for: session)) 筆交易")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    isVirtual ? Color.gray.opacity(0.1) :
                    isPermanent ? Color.purple.opacity(0.1) :
                    Color.blue.opacity(0.1)
                )
        )
    }

    // 場次進度資訊（基於選中的日期）
    private var sessionProgressInfo: String? {
        let calendar = Calendar.current
        let referenceDate = calendar.startOfDay(for: selectedDate)

        switch session.dateType {
        case .single:
            return nil  // 單日場次不顯示

        case .multi:
            // 多日場次：顯示「第 X 天/共 Y 天」
            guard let endDate = session.endDate else { return nil }
            let start = calendar.startOfDay(for: session.startDate)
            let end = calendar.startOfDay(for: endDate)
            let totalDays = calendar.dateComponents([.day], from: start, to: end).day! + 1

            // 計算選中日期是第幾天
            if referenceDate >= start && referenceDate <= end {
                let currentDay = calendar.dateComponents([.day], from: start, to: referenceDate).day! + 1
                return "第 \(currentDay) 天/共 \(totalDays) 天"
            } else {
                return "共 \(totalDays) 天"
            }

        case .permanent:
            // 無限期場次：顯示「開始至今第 X 天」（基於選中日期）
            let start = calendar.startOfDay(for: session.startDate)
            let daysSinceStart = calendar.dateComponents([.day], from: start, to: referenceDate).day! + 1
            return "開始至今第 \(daysSinceStart) 天"
        }
    }
}

// 月份年份選擇器
struct MonthYearPickerView: View {
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
                Picker("年份", selection: $selectedYear) {
                    ForEach(years, id: \.self) { year in
                        Text("\(year)年").tag(year)
                    }
                }
                .pickerStyle(WheelPickerStyle())
                
                Picker("月份", selection: $selectedMonth) {
                    ForEach(months, id: \.self) { month in
                        Text("\(month)月").tag(month)
                    }
                }
                .pickerStyle(WheelPickerStyle())
            }
            .navigationTitle("選擇月份")
            .navigationBarItems(
                leading: Button("取消") {
                    isPresented = false
                },
                trailing: Button("確定") {
                    updateDate()
                    isPresented = false
                }
            )
        }
    }
    
    private func updateDate() {
        let components = DateComponents(year: selectedYear, month: selectedMonth, day: 1)
        if let newDate = calendar.date(from: components) {
            currentDate = newDate
        }
    }
}
