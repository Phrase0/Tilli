//
//  MyView.swift
//  Tilli
//
//  Created by Peiyun on 2025/7/28.
//

import SwiftUI
import Kingfisher

struct MyView: View {

    // MARK: - 認證管理
    @EnvironmentObject var authManager: AuthenticationManager

    // MARK: - 設定狀態
    @AppStorage("selectedLanguage") private var selectedLanguage = "zh-Hant"
    @AppStorage("calculatorEnabled") private var calculatorEnabled = true
    @AppStorage("darkModeEnabled") private var darkModeEnabled = false
    @AppStorage("notificationsEnabled") private var notificationsEnabled = false

    @State private var showTilliProSheet = false
    @State private var showDeleteAccountAlert = false

    // MARK: - App Version
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 16) {
                        userInfoCard
                        topSettingsCard
                        bottomSettingsCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                }

                logOutButton
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                    .background(Color(.systemGroupedBackground))
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("個人資料")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
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
                NavigationLink {
                    SignInView()
                        .environmentObject(authManager)
                } label: {
                    HStack(spacing: 16) {
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
            if let localImage = authManager.localProfileImage {
                Image(uiImage: localImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 70, height: 70)
                    .clipShape(Circle())
            } else if let photoURL = user.photoURL, !photoURL.isEmpty, let url = URL(string: photoURL) {
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

            // 我的收款碼
            NavigationLink {
                MerchantQRCodeView()
            } label: {
                HStack {
                    Image(systemName: "qrcode")
                        .foregroundColor(.secondary)
                        .frame(width: 24)

                    Text("我的收款碼")
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

    // MARK: - 底部按鈕（登入/登出）
    private var logOutButton: some View {
        Group {
            if authManager.isLoggedIn {
                VStack(spacing: 12) {
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

                    Button(action: {
                        showDeleteAccountAlert = true
                    }) {
                        Text("刪除帳號")
                            .font(.footnote)
                            .foregroundColor(.red.opacity(0.7))
                    }
                }
                .alert("確認刪除帳號", isPresented: $showDeleteAccountAlert) {
                    Button("取消", role: .cancel) { }
                    Button("刪除", role: .destructive) {
                        Task { await authManager.deleteAccount() }
                    }
                } message: {
                    Text("帳號刪除後所有資料將永久消失，且無法復原。")
                }
            } else {
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
