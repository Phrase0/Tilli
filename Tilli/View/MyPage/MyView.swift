//
//  MyView.swift
//  Tilli
//
//  Created by Peiyun on 2025/7/28.
//

import SwiftUI
import Kingfisher

struct MyView: View {

    @EnvironmentObject var authManager: AuthenticationManager

    @AppStorage("selectedLanguage") private var selectedLanguage = "zh-Hant"
    @AppStorage("calculatorEnabled") private var calculatorEnabled = true
    @AppStorage("darkModeEnabled") private var darkModeEnabled = false
    @AppStorage("notificationsEnabled") private var notificationsEnabled = false

    @State private var showTilliProSheet = false
    @State private var showDeleteAccountAlert = false

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: DesignSystem.Spacing.lg) {
                        userInfoCard
                        menuCard
                        settingsCard
                    }
                    .padding(.horizontal, DesignSystem.Spacing.md)
                    .padding(.top, DesignSystem.Spacing.md)
                    .padding(.bottom, DesignSystem.Spacing.lg)
                }

                if authManager.isLoggedIn {
                    signOutSection
                        .padding(.horizontal, DesignSystem.Spacing.md)
                        .padding(.vertical, DesignSystem.Spacing.md)
                        .background(DesignSystem.ColorToken.paper)
                }
            }
            .background(DesignSystem.ColorToken.paper)
            // 我的
            .navigationTitle("myPageTitle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if authManager.isLoggedIn {
                        NavigationLink {
                            ProfileEditView(isNewUser: false)
                                .environmentObject(authManager)
                        } label: {
                            Image(systemName: "pencil")
                                .foregroundColor(DesignSystem.ColorToken.ink)
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
        VStack(spacing: DesignSystem.Spacing.md) {
            if authManager.isLoggedIn {
                loggedInUserInfo
            } else {
                notLoggedInUserInfo
            }
        }
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.ColorToken.cardSurface)
        .cornerRadius(DesignSystem.Radius.md)
        .shadow(color: DesignSystem.Shadow.cardColor, radius: DesignSystem.Shadow.cardRadius,
                x: DesignSystem.Shadow.cardX, y: DesignSystem.Shadow.cardY)
    }

    private var loggedInUserInfo: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            profileImageView

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs / 2) {
                if let user = authManager.currentUser {
                    Text(user.name.isEmpty ? String(localized: "myNoName") : user.name)
                        .font(DesignSystem.Typography.title2)
                        .foregroundColor(DesignSystem.ColorToken.ink)

                    Text(user.email)
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.ColorToken.muted)
                }
            }

            Spacer()
        }
    }

    private var notLoggedInUserInfo: some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            Circle()
                .fill(DesignSystem.ColorToken.quietFill)
                .frame(width: 60, height: 60)
                .overlay(
                    Image(systemName: "person.fill")
                        .font(.title2)
                        .foregroundColor(DesignSystem.ColorToken.muted)
                )

            // 尚未登入
            Text("myNotLoggedIn")
                .font(DesignSystem.Typography.title2)
                .foregroundColor(DesignSystem.ColorToken.ink)

            // 登入以同步資料並使用進階功能
            Text("myLoginHint")
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.ColorToken.muted)
                .multilineTextAlignment(.center)

            NavigationLink {
                SignInView()
                    .environmentObject(authManager)
            } label: {
                // 登入 / 註冊
                Text("mySignIn")
                    .font(DesignSystem.Typography.body)
                    .fontWeight(.semibold)
                    .foregroundColor(DesignSystem.ColorToken.onButtonFilled)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DesignSystem.Spacing.md)
                    .background(DesignSystem.ColorToken.buttonFilled)
                    .cornerRadius(DesignSystem.Radius.md)
            }
        }
    }

    // MARK: - 頭像

    @ViewBuilder
    private var profileImageView: some View {
        if let user = authManager.currentUser {
            if let localImage = authManager.localProfileImage {
                Image(uiImage: localImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 60, height: 60)
                    .clipShape(Circle())
            } else if let photoURL = user.photoURL, !photoURL.isEmpty, let url = URL(string: photoURL) {
                KFImage(url)
                    .placeholder {
                        ProgressView()
                            .frame(width: 60, height: 60)
                            .background(DesignSystem.ColorToken.quietFill)
                            .clipShape(Circle())
                    }
                    .onFailure { _ in }
                    .resizable()
                    .scaledToFill()
                    .frame(width: 60, height: 60)
                    .clipShape(Circle())
            } else {
                nameInitialsView(name: user.name)
            }
        }
    }

    private func nameInitialsView(name: String) -> some View {
        ZStack {
            Circle()
                .fill(DesignSystem.ColorToken.quietFill)
                .frame(width: 60, height: 60)

            Text(name.isEmpty ? "?" : String(name.prefix(2)))
                .font(DesignSystem.Typography.title2)
                .foregroundColor(DesignSystem.ColorToken.ink)
        }
    }

    // MARK: - 功能選單卡片

    private var menuCard: some View {
        VStack(spacing: 0) {
            // 會員方案
            Button(action: { showTilliProSheet = true }) {
                menuRow(icon: "crown.fill", iconColor: .orange, titleKey: "myMembership") {
                    if let user = authManager.currentUser {
                        if user.membership == .pro {
                            // Pro 會員
                            Text("myProLabel")
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(.orange)
                        } else {
                            // 免費版
                            Text("myFreeLabel")
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.ColorToken.muted)
                        }
                    }
                    chevron
                }
            }

            rowDivider

            // 我的收款碼
            NavigationLink {
                MerchantQRCodeView()
            } label: {
                menuRow(icon: "qrcode", titleKey: "myQrCode") {
                    chevron
                }
            }

            rowDivider

            // App Version
            menuRow(icon: "info.circle", titleKey: "myAppVersion") {
                Text(verbatim: appVersion)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.ColorToken.muted)
            }
        }
        .background(DesignSystem.ColorToken.cardSurface)
        .cornerRadius(DesignSystem.Radius.md)
        .shadow(color: DesignSystem.Shadow.cardColor, radius: DesignSystem.Shadow.cardRadius,
                x: DesignSystem.Shadow.cardX, y: DesignSystem.Shadow.cardY)
    }

    // MARK: - 設定卡片

    private var settingsCard: some View {
        VStack(spacing: 0) {
            // 語言
            menuRow(icon: "globe", titleKey: "myLanguage") {
                Picker("", selection: $selectedLanguage) {
                    Text(verbatim: "中文").tag("zh-Hant")
                    Text(verbatim: "English").tag("en")
                }
                .labelsHidden()
                .tint(DesignSystem.ColorToken.muted)
            }

            rowDivider

            // 計算機功能
            menuRow(icon: "questionmark.circle", titleKey: "myCalculator") {
                Toggle("", isOn: $calculatorEnabled)
                    .labelsHidden()
            }

            rowDivider

            // 深色模式
            menuRow(icon: "moon", titleKey: "myDarkMode") {
                Toggle("", isOn: $darkModeEnabled)
                    .labelsHidden()
            }

            rowDivider

            // 通知
            menuRow(icon: "bell", titleKey: "myNotifications") {
                Toggle("", isOn: $notificationsEnabled)
                    .labelsHidden()
            }
        }
        .background(DesignSystem.ColorToken.cardSurface)
        .cornerRadius(DesignSystem.Radius.md)
        .shadow(color: DesignSystem.Shadow.cardColor, radius: DesignSystem.Shadow.cardRadius,
                x: DesignSystem.Shadow.cardX, y: DesignSystem.Shadow.cardY)
    }

    // MARK: - 登出區域

    private var signOutSection: some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            // 登出
            Button(action: { authManager.signOut() }) {
                HStack(spacing: DesignSystem.Spacing.xs) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                    // 登出
                    Text("mySignOut")
                }
                .font(DesignSystem.Typography.body)
                .fontWeight(.semibold)
                .foregroundColor(DesignSystem.ColorToken.alertRed)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DesignSystem.Spacing.md)
                .background(DesignSystem.ColorToken.quietFill)
                .cornerRadius(DesignSystem.Radius.md)
            }

            // 刪除帳號
            Button(action: { showDeleteAccountAlert = true }) {
                // 刪除帳號
                Text("myDeleteAccount")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.ColorToken.alertRed.opacity(0.7))
            }
        }
        // 確認刪除帳號
        .alert("myDeleteAccountTitle", isPresented: $showDeleteAccountAlert) {
            // 取消
            Button("commonCancel", role: .cancel) { }
            // 刪除
            Button("commonDelete", role: .destructive) {
                Task { await authManager.deleteAccount() }
            }
        } message: {
            // 帳號刪除後所有資料將永久消失，且無法復原。
            Text("myDeleteAccountMessage")
        }
    }

    // MARK: - 共用元件

    private func menuRow<Trailing: View>(
        icon: String,
        iconColor: Color = DesignSystem.ColorToken.muted,
        titleKey: LocalizedStringKey,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Image(systemName: icon)
                .foregroundColor(iconColor)
                .frame(width: 24)

            Text(titleKey)
                .font(DesignSystem.Typography.body)
                .foregroundColor(DesignSystem.ColorToken.ink)

            Spacer()

            trailing()
        }
        .padding(.horizontal, DesignSystem.Spacing.md)
        .padding(.vertical, DesignSystem.Spacing.sm)
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(DesignSystem.Typography.caption)
            .foregroundColor(DesignSystem.ColorToken.muted)
    }

    private var rowDivider: some View {
        Divider()
            .padding(.leading, DesignSystem.Spacing.md + 24 + DesignSystem.Spacing.sm)
    }
}
