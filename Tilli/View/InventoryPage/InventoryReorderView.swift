//
//  InventoryReorderView.swift
//  Tilli
//
//  排序畫面：組合｜套餐｜各類別分組，各組內拖曳調整順序（不能跨組）。
//  在草稿上操作，按「完成」才寫入，「取消」不變更。列出全部項目（不套搜尋、含已下架）。
//

import SwiftUI

struct InventoryReorderView: View {
    @ObservedObject var viewModel: InventoryViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var draft: ReorderDraft

    init(viewModel: InventoryViewModel) {
        self.viewModel = viewModel
        _draft = State(initialValue: viewModel.makeReorderDraft())
    }

    var body: some View {
        NavigationStack {
            List {
                if !draft.combos.isEmpty {
                    // 組合
                    Section(header: Text("bundleChipCombo")) {
                        ForEach(draft.combos) { row(name: $0.name, isDisabled: $0.isDisabled) }
                            .onMove { draft.combos.move(fromOffsets: $0, toOffset: $1) }
                    }
                }
                if !draft.fixed.isEmpty {
                    // 套餐
                    Section(header: Text("bundleChipFixed")) {
                        ForEach(draft.fixed) { row(name: $0.name, isDisabled: $0.isDisabled) }
                            .onMove { draft.fixed.move(fromOffsets: $0, toOffset: $1) }
                    }
                }
                ForEach(draft.categories.indices, id: \.self) { index in
                    Section(header: Text(verbatim: draft.categories[index].category.name)) {
                        ForEach(draft.categories[index].products) { row(name: $0.name, isDisabled: $0.isDisabled) }
                            .onMove { draft.categories[index].products.move(fromOffsets: $0, toOffset: $1) }
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            // 排序
            .navigationTitle("inventoryReorderTitle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    // 取消
                    Button("commonCancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    // 完成
                    Button("commonDone") {
                        if viewModel.saveOrder(draft) { dismiss() }
                    }
                }
            }
            // 儲存失敗，請再試一次（畫面不關閉，可再按一次完成）
            .alert("bundleSaveFailed", isPresented: $viewModel.reorderSaveFailed) {
                // 確定
                Button("commonConfirm", role: .cancel) { }
            }
        }
    }

    private func row(name: String, isDisabled: Bool) -> some View {
        HStack(spacing: DesignSystem.Spacing.xs) {
            Text(name)
                .font(DesignSystem.Typography.body)
                .foregroundColor(isDisabled ? DesignSystem.ColorToken.muted : DesignSystem.ColorToken.ink)
            if isDisabled {
                // 已下架
                TagLabel("bundleMemberDisabledTag")
            }
        }
    }
}
