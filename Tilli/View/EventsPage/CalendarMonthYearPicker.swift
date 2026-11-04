//
//  CalendarMonthYearPicker.swift
//  Tilli
//
//  行事曆的年月選擇（彈出畫面；只有選年份、月份的畫面狀態，不需要 ViewModel）。
//

import SwiftUI

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
