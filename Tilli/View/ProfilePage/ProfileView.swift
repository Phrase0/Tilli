//
//  ProfileView.swift
//  Tilli
//
//  Created by Peiyun on 2025/4/22.
//

import SwiftUI
import Kingfisher

struct ProfileView: View {

    // MARK: - 認證管理
    @EnvironmentObject var authManager: AuthenticationManager

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
            .toolbar {
                // 右上角編輯按鈕（只在已登入時顯示）
                ToolbarItem(placement: .navigationBarTrailing) {
                    if authManager.isLoggedIn {
                        NavigationLink {
                            ProfileEditView(isNewUser: false)
                                .environmentObject(authManager)
                        } label: {
                            Image(systemName: "pencil")
                                .font(.body)
                        }
                    }
                }
            }
            .sheet(isPresented: $showTilliProSheet) {
                TilliProSheetView()
            }
        }
        .preferredColorScheme(darkModeEnabled ? .dark : .light)
    }

    // MARK: - 用戶資訊卡片
    private var userInfoCard: some View {
        Group {
            if authManager.isLoggedIn {
                // 已登入：顯示用戶資訊（不可點擊）
                HStack(spacing: 16) {
                    profileImageView

                    VStack(alignment: .leading, spacing: 4) {
                        if let user = authManager.currentUser {
                            Text(user.name.isEmpty ? "未設定名稱" : user.name)
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)

                            Text(user.email)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()
                }
                .padding(16)
                .background(Color(.systemBackground))
                .cornerRadius(12)
            } else {
                // 未登入：可點擊進入登入頁
                NavigationLink {
                    SignInView()
                        .environmentObject(authManager)
                } label: {
                    HStack(spacing: 16) {
                        // 灰色圓形 Placeholder
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 70, height: 70)
                            .overlay(
                                Image(systemName: "person.fill")
                                    .font(.title)
                                    .foregroundColor(.gray)
                            )

                        VStack(alignment: .leading, spacing: 4) {
                            Text("尚未登入")
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)

                            Text("登入以同步資料並使用進階功能")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.leading)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    .padding(16)
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }

    // MARK: - 頭像顯示
    @ViewBuilder
    private var profileImageView: some View {
        if let user = authManager.currentUser {
            // 優先顯示本地圖片（剛上傳的）
            if let localImage = authManager.localProfileImage {
                Image(uiImage: localImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 70, height: 70)
                    .clipShape(Circle())
            } else if let photoURL = user.photoURL, !photoURL.isEmpty, let url = URL(string: photoURL) {
                // 沒有本地圖片時，用 Kingfisher 載入
                KFImage(url)
                    .placeholder {
                        ProgressView()
                            .frame(width: 70, height: 70)
                            .background(Color.gray.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .onFailure { _ in }
                    .resizable()
                    .scaledToFill()
                    .frame(width: 70, height: 70)
                    .clipShape(Circle())
            } else {
                nameInitialsView(name: user.name)
            }
        }
    }
    
    // MARK: - 姓名縮寫圓形
    private func nameInitialsView(name: String) -> some View {
        ZStack {
            Circle()
                .fill(Color.blue.opacity(0.2))
                .frame(width: 70, height: 70)

            Text(name.isEmpty ? "?" : String(name.prefix(2)))
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.blue)
        }
    }

    // MARK: - 上方設定卡片
    private var topSettingsCard: some View {
        VStack(spacing: 0) {
            // Tilli Pro
            Button(action: {
                showTilliProSheet = true
            }) {
                HStack {
                    Image(systemName: "crown.fill")
                        .foregroundColor(.orange)
                        .frame(width: 24)

                    Text("Tilli Pro")
                        .foregroundColor(.primary)

                    Spacer()

                    // 顯示會員狀態
                    if let user = authManager.currentUser {
                        Text(user.membership == .pro ? "Pro 會員" : "免費版")
                            .font(.footnote)
                            .foregroundColor(user.membership == .pro ? .orange : .secondary)
                    }

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

    // MARK: - 底部按鈕（登入/登出）
    private var logOutButton: some View {
        Group {
            if authManager.isLoggedIn {
                // 登出按鈕
                Button(action: {
                    authManager.signOut()
                }) {
                    HStack {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                        Text("登出")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.red)
                    .cornerRadius(12)
                }
            } else {
                // 登入按鈕
                NavigationLink {
                    SignInView()
                        .environmentObject(authManager)
                } label: {
                    HStack {
                        Image(systemName: "person.badge.plus")
                        Text("註冊 / 登入")
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
    }
}

// MARK: - Tilli Pro Sheet View
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

                // 測試用：Pro / Free 切換
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

            // 更新本地 currentUser
            authManager.currentUser?.membership = newMembership
            authManager.currentUser?.expiryDate = expiryDate

            // 同步 SyncManager 的會員等級
            SyncManager.shared.setMembership(newMembership)

            // 根據新等級啟動或停止 Listener
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
