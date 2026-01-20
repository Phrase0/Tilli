//
//  ProfileView.swift
//  Tilli
//
//  Created by Peiyun on 2025/4/22.
//

import SwiftUI
import PhotosUI

struct ProfileView: View {

    // MARK: - 認證管理
    @EnvironmentObject var authManager: AuthenticationManager

    // MARK: - 設定狀態
    @AppStorage("selectedLanguage") private var selectedLanguage = "zh-Hant"
    @AppStorage("calculatorEnabled") private var calculatorEnabled = true
    @AppStorage("darkModeEnabled") private var darkModeEnabled = false
    @AppStorage("notificationsEnabled") private var notificationsEnabled = false

    @State private var showTilliProSheet = false
    @State private var showSignInSheet = false

    // MARK: - 編輯模式
    @State private var isEditing = false
    @State private var editedName = ""
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedPhotoData: Data?
    @State private var isUploadingPhoto = false

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
                        Button {
                            if isEditing {
                                // 儲存編輯
                                saveProfile()
                            } else {
                                // 進入編輯模式
                                startEditing()
                            }
                        } label: {
                            Image(systemName: isEditing ? "checkmark" : "pencil")
                                .font(.body)
                        }
                    }
                }

                // 取消編輯按鈕
                ToolbarItem(placement: .navigationBarLeading) {
                    if isEditing {
                        Button("取消") {
                            cancelEditing()
                        }
                    }
                }
            }
            .sheet(isPresented: $showTilliProSheet) {
                TilliProSheetView()
            }
            .sheet(isPresented: $showSignInSheet) {
                SignInSheetView()
                    .environmentObject(authManager)
            }
            .onChange(of: selectedPhotoItem) { _, newItem in
                Task {
                    await loadSelectedPhoto(from: newItem)
                }
            }
        }
        .preferredColorScheme(darkModeEnabled ? .dark : .light)
    }

    // MARK: - 用戶資訊卡片
    private var userInfoCard: some View {
        Button(action: {
            if !authManager.isLoggedIn && !isEditing {
                showSignInSheet = true
            }
        }) {
            HStack(spacing: 16) {
                // 頭像
                profileImageView

                // 用戶資訊
                VStack(alignment: .leading, spacing: 4) {
                    if authManager.isLoggedIn, let user = authManager.currentUser {
                        // 已登入
                        if isEditing {
                            // 編輯模式：顯示文字輸入框
                            TextField("輸入您的名稱", text: $editedName)
                                .font(.title3)
                                .fontWeight(.semibold)
                                .textFieldStyle(.plain)
                        } else {
                            // 顯示模式
                            Text(user.name.isEmpty ? "未設定名稱" : user.name)
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                        }

                        Text(user.email)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    } else {
                        // 未登入
                        Text("尚未登入")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)

                        Text("登入以同步資料並使用進階功能")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                }

                Spacer()

                // 未登入時顯示箭頭
                if !authManager.isLoggedIn {
                    Image(systemName: "chevron.right")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            .padding(16)
            .background(Color(.systemBackground))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isEditing)
    }

    // MARK: - 頭像顯示
    @ViewBuilder
    private var profileImageView: some View {
        if authManager.isLoggedIn, let user = authManager.currentUser {
            // 已登入
            if isEditing {
                // 編輯模式：可點擊選擇照片
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    profileImageContent(user: user)
                        .overlay(
                            ZStack {
                                Circle()
                                    .fill(Color.black.opacity(0.4))

                                Image(systemName: "camera.fill")
                                    .font(.title3)
                                    .foregroundColor(.white)
                            }
                        )
                }
            } else {
                // 顯示模式
                profileImageContent(user: user)
            }
        } else {
            // 未登入：灰色圓形 Placeholder
            Circle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 70, height: 70)
                .overlay(
                    Image(systemName: "person.fill")
                        .font(.title)
                        .foregroundColor(.gray)
                )
        }
    }

    // MARK: - 頭像內容
    @ViewBuilder
    private func profileImageContent(user: UserProfile) -> some View {
        if let photoData = selectedPhotoData, let uiImage = UIImage(data: photoData) {
            // 顯示選擇的新照片
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: 70, height: 70)
                .clipShape(Circle())
        } else if let photoURL = user.photoURL, let url = URL(string: photoURL) {
            // 顯示現有照片
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: 70, height: 70)
                        .clipShape(Circle())
                case .failure, .empty:
                    nameInitialsView(name: user.name)
                @unknown default:
                    nameInitialsView(name: user.name)
                }
            }
        } else {
            // 顯示姓名縮寫
            nameInitialsView(name: user.name)
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

    // MARK: - 編輯操作
    private func startEditing() {
        editedName = authManager.currentUser?.name ?? ""
        selectedPhotoData = nil
        selectedPhotoItem = nil
        isEditing = true
    }

    private func cancelEditing() {
        editedName = ""
        selectedPhotoData = nil
        selectedPhotoItem = nil
        isEditing = false
    }

    private func saveProfile() {
        Task {
            // 更新名稱
            let newName = editedName.isEmpty ? nil : editedName

            // TODO: 上傳照片到 Firebase Storage 並取得 URL
            // 目前先只更新名稱
            await authManager.updateProfile(name: newName, photoURL: nil)

            isEditing = false
            editedName = ""
            selectedPhotoData = nil
            selectedPhotoItem = nil
        }
    }

    private func loadSelectedPhoto(from item: PhotosPickerItem?) async {
        guard let item = item else { return }

        do {
            if let data = try await item.loadTransferable(type: Data.self) {
                selectedPhotoData = data
            }
        } catch {
            print("Error loading photo: \(error)")
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
        Button(action: {
            if authManager.isLoggedIn {
                // 登出
                authManager.signOut()
            } else {
                // 開啟登入 Sheet
                showSignInSheet = true
            }
        }) {
            HStack {
                if authManager.isLoggedIn {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                    Text("登出")
                } else {
                    Image(systemName: "person.badge.plus")
                    Text("註冊 / 登入")
                }
            }
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(authManager.isLoggedIn ? Color.red : Color.blue)
            .cornerRadius(12)
        }
        .disabled(isEditing)
        .opacity(isEditing ? 0.5 : 1)
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
