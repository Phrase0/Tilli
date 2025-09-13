//
//  CalendarView.swift
//  Tilli
//
//  Created by Peiyun on 2025/4/22.
//

import SwiftUI

struct CalendarView: View {
    @EnvironmentObject var sessionDataManager: SessionDataManager
    @EnvironmentObject var transactionDataManager: TransactionDataManager
    @StateObject private var viewModel: CalendarViewModel
    @State private var currentDate = Date()
    @State private var selectedDate = Date()
    @State private var showingMonthYearPicker = false
    @State private var selectedSession: SessionModel = SessionModel(id: UUID(), title: "", date: Date(), categories: [], createdAt: Date(), transactions: [])
    
    init() {
        let defaultSession = SessionModel(id: UUID(), title: "", date: Date(), categories: [], createdAt: Date(), transactions: [])
        _selectedSession = State(initialValue: defaultSession)
        _viewModel = StateObject(wrappedValue: CalendarViewModel(session: .constant(defaultSession)))
    }
    
    private let calendar = Calendar.current
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_TW")
        return formatter
    }()
    
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
                
                Spacer()
            }
            .onAppear {
                viewModel.updateDataManagers(
                    transactionDataManager: transactionDataManager,
                    sessionDataManager: sessionDataManager
                )
                viewModel.refresh(using: sessionDataManager)
            }
            .navigationTitle("我的行事曆")
        }
        
    }
    
    // 月份標題
    private var monthHeader: some View {
        HStack(spacing: 0) {
            Button(action: { changeMonth(-1) }) {
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
            
            Button(action: { changeMonth(1) }) {
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
                DayCell(
                    date: date,
                    isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
                    isToday: calendar.isDateInToday(date),
                    hasSessions: viewModel.hasSessions(on: date),
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
                        changeMonth(-1)
                    } else if value.translation.width < -50 {
                        changeMonth(1)
                    }
                }
        )
    }
    
    // Session 列表
    private var sessionList: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !viewModel.sessionsForDate(selectedDate).isEmpty {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.sessionsForDate(selectedDate)) { session in
                            NavigationLink(destination: SessionDetailFromCalendarView(
                                session: .constant(session)
                            )) {
                                SessionRowView(session: session)
                            }
                        }
                    }
                    .padding(.horizontal, 30)
                    .padding(.top, 20)
                }
            }
        }
    }
    
    
    private func changeMonth(_ direction: Int) {
        if let newDate = viewModel.changeMonth(direction, currentDate: currentDate) {
            currentDate = newDate
        }
    }
}

// 日期單元格
struct DayCell: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let hasSessions: Bool
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
                
                if hasSessions {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 5, height: 5)
                } else {
                    Spacer().frame(height: 5)
                }
            }
            .frame(height: 44)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PlainButtonStyle())
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
    
    var body: some View {
        HStack(alignment: .top) {
            Text(session.title)
                .font(.headline)
                .foregroundColor(.black)

            Spacer()
            
            VStack(alignment: .trailing, spacing: 6) {
                Text("NT$\(totalAmount, specifier: "%.0f")")
                    .font(.headline)
                    .foregroundColor(.blue)
                
                Text("\(session.transactions.count) transactions")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.1))
        )
    }
    
    private var totalAmount: Double {
        session.transactions.reduce(0) { $0 + $1.totalAmount }
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
                Picker("Year", selection: $selectedYear) {
                    ForEach(years, id: \.self) { year in
                        Text("\(year)年").tag(year)
                    }
                }
                .pickerStyle(WheelPickerStyle())
                
                Picker("Month", selection: $selectedMonth) {
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
