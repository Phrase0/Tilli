//
//  VoidTransactionView.swift
//  Tilli
//
//  作廢視窗（sheet，系統 Form 樣式）：交易編號與金額 → 作廢原因（選單＋補充文字）→ 庫存回流與否 → 「作廢」。
//  按「作廢」先跳確認框，確認後由 VM 寫入；成功或已被作廢就關閉視窗（明細頁在關閉後重新讀取），存檔失敗留在視窗提示。
//

import SwiftUI

struct VoidTransactionView: View {
    @EnvironmentObject private var eventRepository: EventRepository
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: VoidTransactionViewModel

    @State private var showConfirm = false
    @State private var showVoidFailed = false

    init(transaction: TransactionModel, dataSource: EventDataSource) {
        _viewModel = StateObject(wrappedValue: VoidTransactionViewModel(transaction: transaction, dataSource: dataSource))
    }

    var body: some View {
        NavigationStack {
            Form {
                headerSection
                reasonSection
                restockSection
                submitSection
            }
            // 作廢交易
            .navigationTitle("voidSheetTitle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    // 取消
                    Button("commonCancel") { dismiss() }
                }
            }
            .alert(viewModel.confirmTitle, isPresented: $showConfirm) {
                // 取消
                Button("commonCancel", role: .cancel) {}
                // 作廢
                Button("voidSubmitButton", role: .destructive) { submit() }
            } message: {
                Text(viewModel.confirmMessage)
            }
            // 作廢失敗，請再試一次
            .alert("voidFailedMessage", isPresented: $showVoidFailed) {
                // 好
                Button("commonOK", role: .cancel) {}
            }
        }
    }

    // MARK: - 交易編號與金額

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxs) {
                Text(viewModel.transactionNumber)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.ColorToken.muted)
                Text(viewModel.amountText)
                    .font(DesignSystem.Typography.title2)
                    .foregroundColor(DesignSystem.ColorToken.ink)
            }
        }
    }

    // MARK: - 作廢原因

    private var reasonSection: some View {
        // 作廢原因
        Section(header: Text("voidReasonSection")) {
            // 原因
            Picker("voidReasonLabel", selection: $viewModel.selectedReason) {
                // 請選擇
                Text("voidReasonPlaceholder").tag(VoidReason?.none)
                ForEach(VoidReason.allCases, id: \.self) { reason in
                    Text(reason.displayName).tag(VoidReason?.some(reason))
                }
            }

            // 請輸入作廢原因
            TextField("voidNotePlaceholder", text: $viewModel.note)
        }
    }

    // MARK: - 庫存

    private var restockSection: some View {
        // 庫存
        Section(
            header: Text("voidRestockSection"),
            // 回流：把這筆交易的商品數量加回庫存
            footer: Text("voidRestockHint")
        ) {
            // 兩段都可為未選，系統 segmented Picker 表示不了，所以用兩個並排按鈕
            HStack(spacing: DesignSystem.Spacing.xxs) {
                // 回流
                restockSegment("voidRestockYes", value: true)
                // 不回流
                restockSegment("voidRestockNo", value: false)
            }
            .padding(DesignSystem.Spacing.xxs / 2)
            .background(DesignSystem.ColorToken.quietFill)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.sm))
        }
    }

    private func restockSegment(_ titleKey: LocalizedStringKey, value: Bool) -> some View {
        let isSelected = viewModel.restockChoice == value
        return Button {
            viewModel.restockChoice = value
        } label: {
            Text(titleKey)
                .font(DesignSystem.Typography.body)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundColor(isSelected ? DesignSystem.ColorToken.paper : DesignSystem.ColorToken.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DesignSystem.Spacing.xs)
                .background(isSelected ? DesignSystem.ColorToken.ink : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.sm))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 作廢按鈕（靜謐填色底＋警示紅字，不可按時字變灰）

    private var submitSection: some View {
        Section {
            Button {
                showConfirm = true
            } label: {
                // 作廢
                Text("voidSubmitButton")
                    .font(DesignSystem.Typography.body)
                    .fontWeight(.semibold)
                    .foregroundColor(viewModel.canSubmit ? DesignSystem.ColorToken.alertRed : DesignSystem.ColorToken.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DesignSystem.Spacing.md)
                    .background(DesignSystem.ColorToken.quietFill)
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.md))
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canSubmit)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
    }

    // MARK: - 寫入

    private func submit() {
        let outcome = viewModel.performVoid(eventRepository: eventRepository)
        switch outcome {
        case .done, .rejected:
            // 已作廢等被拒絕的情況也關閉，明細頁關閉後會重新讀取
            dismiss()
        case .voidFailed:
            showVoidFailed = true
        }
    }
}
