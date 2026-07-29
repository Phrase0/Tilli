//
//  SessionCardView.swift
//  Tilli
//
//  Created by Peiyun on 2025/1/12.
//

import SwiftUI

enum SessionCardStyle {
    case standard
    case simple
}

struct SessionCardView: View {
    let session: SessionModel
    let style: SessionCardStyle

    var onDuplicate: (() -> Void)? = nil
    var onEdit: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            // Row 1: Title + menu
            HStack(alignment: .firstTextBaseline) {
                Text(session.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(DesignSystem.ColorToken.ink)
                    .lineLimit(1)

                Spacer(minLength: DesignSystem.Spacing.xs)

                if style == .standard {
                    menuButton
                }
            }

            // Row 2: Status pill + date range
            HStack(spacing: DesignSystem.Spacing.xs) {
                statusBadge

                Text(session.displayDateRange)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.ColorToken.muted)
                    .lineLimit(1)
            }
        }
        .padding(DesignSystem.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignSystem.ColorToken.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.md))
        .shadow(
            color: DesignSystem.Shadow.cardColor,
            radius: DesignSystem.Shadow.cardRadius,
            x: DesignSystem.Shadow.cardX,
            y: DesignSystem.Shadow.cardY
        )
    }

    // MARK: - Menu Button

    @ViewBuilder
    private var menuButton: some View {
        if let onDuplicate = onDuplicate,
           let onEdit = onEdit,
           let onDelete = onDelete {
            Menu {
                Button {
                    onEdit()
                } label: {
                    // 編輯場次
                    Label("addSessionEditTitle", systemImage: "pencil")
                }

                Button {
                    onDuplicate()
                } label: {
                    // 複製場次
                    Label("eventsDuplicateTitle", systemImage: "doc.on.doc")
                }

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    // 刪除場次
                    Label("commonDelete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .rotationEffect(.degrees(90))
                    .font(DesignSystem.Typography.body)
                    .foregroundColor(DesignSystem.ColorToken.muted)
                    .frame(width: 32, height: 24)
                    .contentShape(Rectangle())
            }
        }
    }

    // MARK: - Status Badge

    private var statusBadge: some View {
        Text(session.status.localizedDescription)
            .font(DesignSystem.Typography.caption)
            .foregroundColor(session.status.textColor)
            .padding(.horizontal, DesignSystem.Spacing.xs)
            .padding(.vertical, 3)
            .background(session.status.color)
            .clipShape(Capsule())
    }
}
