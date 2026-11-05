//
//  CheckoutFlowView.swift
//  Tilli
//
//  Created by Peiyun on 2025/12/29.
//

import SwiftUI

// MARK: - Environment Key for closing checkout flow
/// 付款寫入成功後呼叫，傳入這筆的總金額（POS 頁用來顯示「付款完成」通知）
private struct CloseCheckoutFlowKey: EnvironmentKey {
    static let defaultValue: (Decimal) -> Void = { _ in }
}

extension EnvironmentValues {
    var closeCheckoutFlow: (Decimal) -> Void {
        get { self[CloseCheckoutFlowKey.self] }
        set { self[CloseCheckoutFlowKey.self] = newValue }
    }
}

struct CheckoutFlowView: View {
    @Binding var isPresented: Bool
    /// 付款成功時設為該筆總金額，POS 頁處理完後設回 nil
    @Binding var completedAmount: Decimal?
    /// 訂單摘要即時讀購物車定價（取消／恢復組合要立刻重算）
    @ObservedObject var posViewModel: POSViewModel

    var body: some View {
        NavigationStack {
            CheckoutSummaryView(posViewModel: posViewModel)
        }
        .environment(\.closeCheckoutFlow, { amount in
            completedAmount = amount
            isPresented = false
        })
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - 結帳失敗提示（現金與電子支付共用）

extension View {
    /// 結帳寫入失敗時的系統提示框；按「好」後留在付款頁，可直接再按一次完成付款
    func checkoutFailedAlert(isPresented: Binding<Bool>) -> some View {
        // 結帳失敗
        alert("checkoutFailedTitle", isPresented: isPresented) {
            // 好
            Button("commonOK", role: .cancel) {}
        } message: {
            // 交易沒有儲存，請再試一次
            Text("checkoutFailedMessage")
        }
    }
}
