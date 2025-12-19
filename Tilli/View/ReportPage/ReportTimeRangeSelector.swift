//
//  ReportTimeRangeSelector.swift
//  Tilli
//
//  Created by Claude on 2025/11/18.
//

import SwiftUI

/// 報表時間範圍選擇器
struct ReportTimeRangeSelector: View {
    let session: SessionModel
    @Binding var selectedRange: ReportTimeRange

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 場次資訊
            HStack(spacing: 8) {
                Image(systemName: dateIcon)
                    .foregroundColor(iconColor)
                    .font(.subheadline)

                Text(session.displayDateRange)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            // 時間範圍選擇
            rangeSelector

            // 自訂日期選擇器
            if selectedRange.type == .custom {
                customDatePicker
            }

            // 顯示實際報表範圍
            HStack {
                Image(systemName: "chart.bar.doc.horizontal")
                    .foregroundColor(.blue)
                    .font(.caption)

                Text("統計範圍：\(selectedRange.displayText)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Text("共 \(selectedRange.dayCount) 天")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    // MARK: - 範圍選擇器

    @ViewBuilder
    private var rangeSelector: some View {
        switch session.dateType {
        case .single:
            // 單日場次：不顯示選擇器
            EmptyView()

        case .multi:
            if let days = session.dayCount {
                // 多日場次：提供全部、今日、（超過7天時）最近7天、自訂選項
                Menu {
                    Button("全部") {
                        selectedRange.type = .all
                    }
                    Button("今日") {
                        selectedRange.type = .today
                    }
                    // 超過 7 天才顯示「最近7天」
                    if days > 7 {
                        Button("最近7天") {
                            selectedRange.type = .recent7
                        }
                    }
                    Button("自訂") {
                        selectedRange.type = .custom
                    }
                } label: {
                    HStack {
                        Text(selectedRangeLabel)
                            .foregroundColor(.primary)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                }
            }

        case .permanent:
            // 無限期場次：提供全部、今日、最近7天、最近30天、自訂選項（自訂最多90天）
            Menu {
                Button("全部") {
                    selectedRange.type = .all
                }
                Button("今日") {
                    selectedRange.type = .today
                }
                Button("最近7天") {
                    selectedRange.type = .recent7
                }
                Button("最近30天") {
                    selectedRange.type = .recent30
                }
                Button("自訂") {
                    selectedRange.type = .custom
                }
            } label: {
                HStack {
                    Text(selectedRangeLabel)
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.systemGray6))
                .cornerRadius(8)
            }
        }
    }

    // MARK: - 自訂日期選擇器

    private var customDatePicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                // 開始日期
                VStack(alignment: .leading, spacing: 4) {
                    Text("開始")
                        .font(.caption)
                        .foregroundColor(.secondary)

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
                    .foregroundColor(.secondary)

                // 結束日期
                VStack(alignment: .leading, spacing: 4) {
                    Text("結束")
                        .font(.caption)
                        .foregroundColor(.secondary)

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
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.caption)

                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
    }

    // MARK: - Helper

    private var selectedRangeLabel: String {
        switch selectedRange.type {
        case .all:
            return "全部"
        case .today:
            return "今日"
        case .recent7:
            return "最近7天"
        case .recent30:
            return "最近30天"
        case .custom:
            return "自訂"
        }
    }

    private var dateIcon: String {
        switch session.dateType {
        case .single:
            return "calendar"
        case .multi:
            return "calendar.badge.clock"
        case .permanent:
            return "infinity"
        }
    }

    private var iconColor: Color {
        switch session.dateType {
        case .single, .multi:
            return .blue
        case .permanent:
            return .purple
        }
    }

    // MARK: - 日期範圍限制

    /// 開始日期的可選範圍
    private var startDateRange: ClosedRange<Date> {
        let calendar = Calendar.current
        let sessionStart = calendar.startOfDay(for: session.startDate)
        let customEnd = calendar.startOfDay(for: selectedRange.customEnd)

        // 開始日期：不可早於場次開始日期，不可晚於結束日期
        return sessionStart...customEnd
    }

    /// 結束日期的可選範圍
    private var endDateRange: ClosedRange<Date> {
        let calendar = Calendar.current
        let customStart = calendar.startOfDay(for: selectedRange.customStart)
        let today = calendar.startOfDay(for: Date())

        // 結束日期的上限
        let upperLimit: Date
        if session.dateType == .permanent {
            // 無限期場次：限制最多90天，且不可超過今天
            let maxEnd = calendar.date(byAdding: .day, value: 89, to: customStart)!
            upperLimit = min(maxEnd, today)
        } else if let sessionEnd = session.endDate {
            // 多日場次：不可超過場次結束日期
            let sessionEndDay = calendar.startOfDay(for: sessionEnd)
            upperLimit = sessionEndDay
        } else {
            // 單日場次（理論上不會到這裡）
            upperLimit = today
        }

        // 結束日期：不可早於開始日期，不可超過上限
        return customStart...upperLimit
    }
}
