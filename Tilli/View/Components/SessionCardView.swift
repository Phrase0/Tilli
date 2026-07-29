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
    var transactionCount: Int = 0
    var transactionTotal: Decimal = 0

    var onDuplicate: (() -> Void)? = nil
    var onEdit: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
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

            Text(session.displayTimeInfo)
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.ColorToken.muted)
                .lineLimit(1)

            if transactionCount > 0 {
                Divider()

                HStack {
                    Text("eventsTransactionCount \(transactionCount)")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.ColorToken.muted)

                    Spacer()

                    Text(transactionTotal.money(currency: session.currency))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(DesignSystem.ColorToken.ink)
                }
            }
        }
        .padding(DesignSystem.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignSystem.ColorToken.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .stroke(DesignSystem.Border.cardColor, lineWidth: DesignSystem.Border.cardWidth)
        )
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
                    Label("addSessionEditTitle", systemImage: "pencil")
                }

                Button {
                    onDuplicate()
                } label: {
                    Label("eventsDuplicateTitle", systemImage: "doc.on.doc")
                }

                Button(role: .destructive) {
                    onDelete()
                } label: {
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
}
