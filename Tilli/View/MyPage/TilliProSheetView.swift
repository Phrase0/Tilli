//
//  TilliProSheetView.swift
//  Tilli
//
//  Created by Peiyun.
//

import SwiftUI

struct TilliProSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authManager: AuthenticationManager

    private var isPro: Bool {
        authManager.currentUser?.membership == .pro
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: DesignSystem.Spacing.lg) {
                Spacer()

                Image(systemName: isPro ? "crown.fill" : "crown")
                    .font(.system(size: 60))
                    .foregroundColor(.orange)

                // Pro 會員 / 免費版
                Text(isPro ? "tilliProMember" : "tilliProFree")
                    .font(.title)
                    .fontWeight(.bold)

                if isPro {
                    if let expiryDate = authManager.currentUser?.expiryDate {
                        // 到期日：...
                        Text("tilliProExpiry \(expiryDate.formatted(date: .abbreviated, time: .omitted))")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                } else {
                    // 升級 Pro 以啟用多裝置即時同步
                    Text("tilliProUpgradeHint")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                #if DEBUG
                VStack(spacing: DesignSystem.Spacing.sm) {
                    Divider()

                    // 測試專用
                    Text("tilliProDebugLabel")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    // Pro 會員 / 免費版
                    Toggle(isPro ? String.localized("tilliProMember") : String.localized("tilliProFree"), isOn: Binding(
                        get: { isPro },
                        set: { newValue in
                            Task {
                                await authManager.toggleMembershipForDebug(toPro: newValue)
                            }
                        }
                    ))
                    .padding(.horizontal, DesignSystem.Spacing.md)
                }
                .padding(.bottom, DesignSystem.Spacing.md)
                #endif
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Tilli Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    // 關閉
                    Button("commonClose") {
                        dismiss()
                    }
                }
            }
        }
    }

}
