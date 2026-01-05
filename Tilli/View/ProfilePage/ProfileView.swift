//
//  ProfileView.swift
//  Tilli
//
//  Created by Peiyun on 2025/4/22.
//

import SwiftUI

struct ProfileView: View {

    // MARK: - 假資料
    private let userName = "王小明"
    private let userEmail = "xiaoming@example.com"

    // MARK: - 設定狀態
    @AppStorage("selectedLanguage") private var selectedLanguage = "zh-Hant"
    @AppStorage("calculatorEnabled") private var calculatorEnabled = true
    @AppStorage("darkModeEnabled") private var darkModeEnabled = false
    @AppStorage("notificationsEnabled") private var notificationsEnabled = false

    @State private var showTilliProSheet = false

    // MARK: - App Version
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 16) {
                        // 用戶資訊卡片
                        userInfoCard

                        // 上方方塊：Tilli Pro、App Version
                        topSettingsCard

                        // 下方方塊：語言、計算機功能、深色模式、通知
                        bottomSettingsCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                }

                // Log Out 按鈕（置底）
                logOutButton
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                    .background(Color(.systemGroupedBackground))
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("個人資料")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showTilliProSheet) {
                TilliProSheetView()
            }
        }
        .preferredColorScheme(darkModeEnabled ? .dark : .light)
    }

    // MARK: - 用戶資訊卡片
    private var userInfoCard: some View {
        HStack(spacing: 16) {
            // 頭像（顯示姓名縮寫）
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.2))
                    .frame(width: 70, height: 70)

                Text(userNameInitials)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.blue)
            }

            // 用戶資訊
            VStack(alignment: .leading, spacing: 4) {
                Text(userName)
                    .font(.title3)
                    .fontWeight(.semibold)

                Text(userEmail)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }

    // MARK: - 姓名縮寫
    private var userNameInitials: String {
        let components = userName.prefix(2)
        return String(components)
    }

    // MARK: - 上方設定卡片
    private var topSettingsCard: some View {
        VStack(spacing: 0) {
            // Tilli Pro
            Button(action: {
                showTilliProSheet = true
            }) {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundColor(.secondary)
                        .frame(width: 24)

                    Text("Tilli Pro")
                        .foregroundColor(.primary)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }

            Divider()
                .padding(.leading, 56)

            // App Version
            HStack {
                Image(systemName: "info.circle")
                    .foregroundColor(.secondary)
                    .frame(width: 24)

                Text("App Version")
                    .foregroundColor(.primary)

                Spacer()

                Text(appVersion)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }

    // MARK: - 下方設定卡片
    private var bottomSettingsCard: some View {
        VStack(spacing: 0) {
            // 語言
            HStack {
                Image(systemName: "globe")
                    .foregroundColor(.secondary)
                    .frame(width: 24)

                Text("語言")
                    .foregroundColor(.primary)

                Spacer()

                Picker("", selection: $selectedLanguage) {
                    Text("中文").tag("zh-Hant")
                    Text("English").tag("en")
                }
                .labelsHidden()
                .tint(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()
                .padding(.leading, 56)

            // 計算機功能
            HStack {
                Image(systemName: "questionmark.circle")
                    .foregroundColor(.secondary)
                    .frame(width: 24)

                Text("計算機功能")
                    .foregroundColor(.primary)

                Spacer()

                Toggle("", isOn: $calculatorEnabled)
                    .labelsHidden()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()
                .padding(.leading, 56)

            // 深色模式
            HStack {
                Image(systemName: "moon")
                    .foregroundColor(.secondary)
                    .frame(width: 24)

                Text("深色模式")
                    .foregroundColor(.primary)

                Spacer()

                Toggle("", isOn: $darkModeEnabled)
                    .labelsHidden()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()
                .padding(.leading, 56)

            // 通知
            HStack {
                Image(systemName: "bell")
                    .foregroundColor(.secondary)
                    .frame(width: 24)

                Text("通知")
                    .foregroundColor(.primary)

                Spacer()

                Toggle("", isOn: $notificationsEnabled)
                    .labelsHidden()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }

    // MARK: - Log Out 按鈕
    private var logOutButton: some View {
        Button(action: {
            // TODO: 實作登出功能
        }) {
            HStack {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                Text("登出")
            }
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.blue)
            .cornerRadius(12)
        }
    }
}

// MARK: - Tilli Pro Sheet View
struct TilliProSheetView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack {
                Spacer()
                Text("Tilli Pro")
                    .font(.title)
                    .foregroundColor(.secondary)
                Spacer()
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
}
