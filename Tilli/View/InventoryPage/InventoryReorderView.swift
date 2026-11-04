//
//  InventoryReorderView.swift
//  Tilli
//
//  排序畫面：組合｜套餐｜各類別分組，各組內拖曳調整順序（不能跨組）。
//  每列左邊是 ≡，按住整列拖曳（與編輯場次的類別列表同一套操作）。
//  在草稿上操作，按「完成」才寫入，「取消」不變更。列出全部項目（不套搜尋、含已下架）。
//

import SwiftUI

struct InventoryReorderView: View {
    @EnvironmentObject private var productRepository: ProductRepository
    @EnvironmentObject private var eventRepository: EventRepository
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: InventoryReorderViewModel

    /// - Parameter onDataChanged: 有寫入資料庫時呼叫（管理頁重新載入）
    init(dataSource: EventDataSource, onDataChanged: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: InventoryReorderViewModel(
            dataSource: dataSource,
            onDataChanged: onDataChanged
        ))
    }

    var body: some View {
        NavigationStack {
            List {
                if !viewModel.draft.combos.isEmpty {
                    // 組合
                    Section(header: Text("bundleChipCombo")) {
                        ForEach(viewModel.draft.combos) { row(name: $0.name, isDisabled: $0.isDisabled) }
                            .onMove(perform: viewModel.moveCombos)
                    }
                }
                if !viewModel.draft.fixed.isEmpty {
                    // 套餐
                    Section(header: Text("bundleChipFixed")) {
                        ForEach(viewModel.draft.fixed) { row(name: $0.name, isDisabled: $0.isDisabled) }
                            .onMove(perform: viewModel.moveFixed)
                    }
                }
                ForEach(viewModel.draft.categories.indices, id: \.self) { index in
                    Section(header: Text(verbatim: viewModel.draft.categories[index].category.name)) {
                        ForEach(viewModel.draft.categories[index].products) { row(name: $0.name, isDisabled: $0.isDisabled) }
                            .onMove { viewModel.moveProducts(inGroup: index, from: $0, to: $1) }
                    }
                }
            }
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
                        if viewModel.save() { dismiss() }
                    }
                }
            }
            // 儲存失敗，請再試一次（畫面不關閉，可再按一次完成）
            .alert("bundleSaveFailed", isPresented: $viewModel.saveFailed) {
                // 確定
                Button("commonConfirm", role: .cancel) { }
            }
        }
        .onAppear {
            viewModel.updateRepositories(productRepository: productRepository, eventRepository: eventRepository)
        }
    }

    private func row(name: String, isDisabled: Bool) -> some View {
        HStack(spacing: DesignSystem.Spacing.xs) {
            Image(systemName: "line.3.horizontal")
                .foregroundColor(DesignSystem.ColorToken.muted)
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
