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
                if days <= 30 {
                    // 多日場次 ≤30天
                    Picker("報表範圍", selection: $selectedRange.type) {
                        Text("全部").tag(ReportTimeRange.RangeType.all)
                        Text("自訂").tag(ReportTimeRange.RangeType.custom)
                    }
                    .pickerStyle(.segmented)
                } else {
                    // 多日場次 >30天
                    Picker("報表範圍", selection: $selectedRange.type) {
                        Text("全部").tag(ReportTimeRange.RangeType.all)
                        Text("最近30天").tag(ReportTimeRange.RangeType.recent30)
                        Text("自訂").tag(ReportTimeRange.RangeType.custom)
                    }
                    .pickerStyle(.segmented)
                }
            }

        case .permanent:
            // 無限期場次：必須選擇，最多90天
            Picker("報表範圍", selection: $selectedRange.type) {
                Text("最近30天").tag(ReportTimeRange.RangeType.recent30)
                Text("自訂").tag(ReportTimeRange.RangeType.custom)
            }
            .pickerStyle(.segmented)
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

                    DatePicker("", selection: $selectedRange.customStart, displayedComponents: .date)
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

                    DatePicker("", selection: $selectedRange.customEnd, displayedComponents: .date)
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
}
