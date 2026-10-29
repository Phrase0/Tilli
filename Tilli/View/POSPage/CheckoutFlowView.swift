//
//  CheckoutFlowView.swift
//  Tilli
//
//  Created by Peiyun on 2025/12/29.
//

import SwiftUI

// MARK: - Environment Key for closing checkout flow
private struct CloseCheckoutFlowKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    var closeCheckoutFlow: () -> Void {
        get { self[CloseCheckoutFlowKey.self] }
        set { self[CloseCheckoutFlowKey.self] = newValue }
    }
}

struct CheckoutFlowView: View {
    @Binding var isPresented: Bool
    @Binding var checkoutCompleted: Bool
    /// 訂單摘要即時讀購物車定價（取消／恢復組合要立刻重算）
    @ObservedObject var posViewModel: POSViewModel

    var body: some View {
        NavigationStack {
            CheckoutSummaryView(posViewModel: posViewModel)
        }
        .environment(\.closeCheckoutFlow, {
            checkoutCompleted = true
            isPresented = false
        })
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}
