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
    @Binding var session: SessionModel

    let selectedItems: [SummaryItemModel]
    let totalAmount: Decimal
    let selectedDiscount: DiscountModel?

    var body: some View {
        NavigationStack {
            CheckoutSummaryView(
                selectedItems: selectedItems,
                totalAmount: totalAmount,
                selectedDiscount: selectedDiscount,
                session: $session
            )
        }
        .environment(\.closeCheckoutFlow, {
            checkoutCompleted = true
            isPresented = false
        })
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}
