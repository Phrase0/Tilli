//
//  ReportTimeRangeSelector.swift
//  Tilli
//
//  Created by Peiyun on 2025/11/18.
//

import SwiftUI

/// 報表時間範圍選擇器
struct ReportTimeRangeSelector: View {
    let event: EventModel
    @Binding var selectedRange: ReportTimeRange

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxs) {
            // 時間範圍選擇
            rangeSelector

            // 自訂日期選擇器
            if selectedRange.type == .custom {
                customDatePicker
            }

            // 顯示實際報表範圍
            HStack {
                Image(systemName: "chart.bar.doc.horizontal")
                    .foregroundColor(DesignSystem.ColorToken.ink)
                    .font(DesignSystem.Typography.caption)

                // 統計範圍：
                Text("timeRangeStatsLabel \(selectedRange.displayText)")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.ColorToken.muted)

                Spacer()

                // 共 N 天
                Text("timeRangeDayCount \(selectedRange.dayCount)")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.ColorToken.muted)
            }
        }
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.ColorToken.paper)
        .cornerRadius(DesignSystem.Radius.sm)
    }

    // MARK: - 範圍選擇器

    @ViewBuilder
    private var rangeSelector: some View {
        switch event.dateType {
        // 單日場次：不顯示選擇器
        case .single:
            EmptyView()

        // 多日場次：提供全部、今日、（超過7天時）最近7天、自訂選項
        case .multi:
            if let days = event.dayCount {
                Menu {
                    // 全部
                    Button("timeRangeAll") {
                        selectedRange.type = .all
                    }
                    // 今日
                    Button("timeRangeToday") {
                        selectedRange.type = .today
                    }
                    // 超過 7 天才顯示「最近7天」
                    if days > 7 {
                        // 最近7天
                        Button("timeRangeRecent7") {
                            selectedRange.type = .recent7
                        }
                    }
                    // 自訂
                    Button("timeRangeCustom") {
                        selectedRange.type = .custom
                    }
                } label: {
                    rangeSelectorLabel
                }
            }

        // 無限期場次：提供全部、今日、最近7天、最近30天、自訂選項（自訂最多90天）
        case .permanent:
            Menu {
                // 全部
                Button("timeRangeAll") {
                    selectedRange.type = .all
                }
                // 今日
                Button("timeRangeToday") {
                    selectedRange.type = .today
                }
                // 最近7天
                Button("timeRangeRecent7") {
                    selectedRange.type = .recent7
                }
                // 最近30天
                Button("timeRangeRecent30") {
                    selectedRange.type = .recent30
                }
                // 自訂
                Button("timeRangeCustom") {
                    selectedRange.type = .custom
                }
            } label: {
                rangeSelectorLabel
            }
        }
    }

    private var rangeSelectorLabel: some View {
        HStack {
            Text(selectedRangeLabel)
                .foregroundColor(DesignSystem.ColorToken.ink)
            Spacer()
            Image(systemName: "chevron.down")
                .foregroundColor(DesignSystem.ColorToken.muted)
                .font(DesignSystem.Typography.caption)
        }
        .padding(.horizontal, DesignSystem.Spacing.sm)
        .padding(.vertical, DesignSystem.Spacing.xs)
        .background(DesignSystem.ColorToken.paper)
        .cornerRadius(DesignSystem.Radius.sm)
    }

    // MARK: - 自訂日期選擇器

    private var customDatePicker: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            HStack(spacing: DesignSystem.Spacing.md) {
                // 開始日期
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxs) {
                    // 開始
                    Text("timeRangeStart")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.ColorToken.muted)

                    DatePicker(
                        "",
                        selection: $selectedRange.customStart,
                        in: startDateRange,
                        displayedComponents: .date
                    )
                    .labelsHidden()
                    .datePickerStyle(.compact)
                }

                Text("～")
                    .foregroundColor(DesignSystem.ColorToken.muted)

                // 結束日期
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxs) {
                    // 結束
                    Text("timeRangeEnd")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.ColorToken.muted)

                    DatePicker(
                        "",
                        selection: $selectedRange.customEnd,
                        in: endDateRange,
                        displayedComponents: .date
                    )
                    .labelsHidden()
                    .datePickerStyle(.compact)
                }
            }

            // 驗證提示
            validationWarning
        }
    }

    // MARK: - 驗證提示

    @ViewBuilder
    private var validationWarning: some View {
        let validation = selectedRange.validateCustomRange()

        if !validation.isValid, let errorMessage = validation.errorMessage {
            HStack(spacing: DesignSystem.Spacing.xxs) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(DesignSystem.Typography.caption)

                Text(errorMessage)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(.orange)
            }
        }
    }

    // MARK: - Helper

    private var selectedRangeLabel: String {
        switch selectedRange.type {
        case .all:
            return String.localized("timeRangeAll")
        case .today:
            return String.localized("timeRangeToday")
        case .recent7:
            return String.localized("timeRangeRecent7")
        case .recent30:
            return String.localized("timeRangeRecent30")
        case .custom:
            return String.localized("timeRangeCustom")
        }
    }

    // MARK: - 日期範圍限制

    /// 開始日期的可選範圍
    private var startDateRange: ClosedRange<Date> {
        let calendar = Calendar.current
        // 開始日期：不可早於場次開始日期，不可晚於結束日期
        let eventStart = calendar.startOfDay(for: event.startDate)
        let customEnd = calendar.startOfDay(for: selectedRange.customEnd)
        return eventStart...customEnd
    }

    /// 結束日期的可選範圍
    private var endDateRange: ClosedRange<Date> {
        let calendar = Calendar.current
        let customStart = calendar.startOfDay(for: selectedRange.customStart)
        let today = calendar.startOfDay(for: Date())

        // 結束日期的上限
        let upperLimit: Date
        if event.dateType == .permanent {
            // 無限期場次：限制最多90天，且不可超過今天
            let maxEnd = calendar.date(byAdding: .day, value: 89, to: customStart)!
            upperLimit = min(maxEnd, today)
        } else if let eventEnd = event.endDate {
            // 多日場次：不可超過場次結束日期
            let eventEndDay = calendar.startOfDay(for: eventEnd)
            upperLimit = eventEndDay
        } else {
            // 單日場次（理論上不會到這裡）
            upperLimit = today
        }

        // 結束日期：不可早於開始日期，不可超過上限
        return customStart...upperLimit
    }
}
