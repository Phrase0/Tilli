//
//  SessionCardView.swift
//  Tilli
//
//  Created by Peiyun on 2025/1/12.
//

import SwiftUI

/// 場次卡片樣式
enum SessionCardStyle {
    case standard       // 標準樣式（SessionsView 使用，有 menu）
    case simple         // 簡化樣式（InventoryTabView 使用，無 menu）
}

/// 共用的場次卡片元件
struct SessionCardView: View {
    let session: SessionModel
    let style: SessionCardStyle

    // 標準樣式的 menu actions
    var onDuplicate: (() -> Void)? = nil
    var onEdit: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(session.title)
                        .font(.headline)
                        .lineLimit(1)

                    Text(session.displayDateRange)
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 12) {
                    // 標準樣式顯示 menu
                    if style == .standard {
                        menuButton
                    }

                    statusBadge
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(session.status == .ongoing ? Color.blue.opacity(0.1) : Color.white)
        )
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
    }

    // MARK: - Menu Button（標準樣式）

    @ViewBuilder
    private var menuButton: some View {
        if let onDuplicate = onDuplicate,
           let onEdit = onEdit,
           let onDelete = onDelete {
            Menu {
                Button {
                    onDuplicate()
                } label: {
                    Label("複製場次", systemImage: "doc.on.doc")
                }

                Button {
                    onEdit()
                } label: {
                    Label("編輯", systemImage: "pencil")
                }

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("刪除", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .rotationEffect(.degrees(90))
                    .foregroundColor(.gray)
                    .padding(8)
            }
        }
    }

    // MARK: - 狀態標籤

    private var statusBadge: some View {
        Text(session.status.localizedDescription)
            .font(.caption)
            .foregroundColor(session.status.textColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(session.status.color)
            .clipShape(Capsule())
    }
}
