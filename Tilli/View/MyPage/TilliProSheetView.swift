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
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: isPro ? "crown.fill" : "crown")
                    .font(.system(size: 60))
                    .foregroundColor(.orange)

                Text(isPro ? "Pro 會員" : "免費版")
                    .font(.title)
                    .fontWeight(.bold)

                if isPro {
                    if let expiryDate = authManager.currentUser?.expiryDate {
                        Text("到期日：\(expiryDate.formatted(date: .abbreviated, time: .omitted))")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("升級 Pro 以啟用多裝置即時同步")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                #if DEBUG
                VStack(spacing: 12) {
                    Divider()

                    Text("測試專用")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Toggle(isPro ? "Pro 會員" : "免費版", isOn: Binding(
                        get: { isPro },
                        set: { newValue in
                            Task {
                                await toggleMembership(toPro: newValue)
                            }
                        }
                    ))
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 16)
                #endif
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Tilli Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("關閉") {
                        dismiss()
                    }
                }
            }
        }
    }

    #if DEBUG
    private func toggleMembership(toPro: Bool) async {
        guard let user = authManager.currentUser else { return }
        let newMembership: UserProfile.Membership = toPro ? .pro : .free
        let expiryDate: Date? = toPro ? Calendar.current.date(byAdding: .year, value: 1, to: Date()) : nil

        do {
            let userRepository = UserRepository()
            try await userRepository.updateMembership(uid: user.uid, membership: newMembership, expiryDate: expiryDate)

            authManager.currentUser?.membership = newMembership
            authManager.currentUser?.expiryDate = expiryDate

            SyncManager.shared.setMembership(newMembership)

            if newMembership == .pro {
                SyncManager.shared.startListening()
            } else {
                SyncManager.shared.stopListening()
            }
        } catch {
            print("❌ 切換會員等級失敗: \(error)")
        }
    }
    #endif
}
