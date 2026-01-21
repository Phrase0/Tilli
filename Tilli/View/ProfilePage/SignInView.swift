//
//  SignInView.swift
//  Tilli
//
//  Created by Peiyun on 2025/1/20.
//

import SwiftUI

struct SignInView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authManager: AuthenticationManager

    /// 控制是否顯示新用戶個人資料設定
    @State private var showProfileSetup = false

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                // Logo 或標題區
                VStack(spacing: 8) {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 80))
                        .foregroundColor(.blue)

                    Text("歡迎來到 Tilli")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("登入以同步資料並使用進階功能")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Spacer()

                // 登入按鈕區
                VStack(spacing: 16) {
                    // Apple 登入按鈕（待實作）
                    Button {
                        // TODO: 實作 Apple Sign In
                        // authManager.signInWithApple()
                    } label: {
                        HStack {
                            Image(systemName: "apple.logo")
                                .font(.title3)
                            Text("使用 Apple 登入")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.black)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(true)
                    .opacity(0.5)

                    // Google 登入按鈕
                    Button {
                        Task {
                            let isNewUser = await authManager.signInWithGoogle()
                            // 登入成功後檢查是否為新用戶
                            if authManager.errorMessage == nil && authManager.isLoggedIn {
                                if isNewUser {
                                    // 新用戶：顯示個人資料設定
                                    showProfileSetup = true
                                } else {
                                    // 既有用戶：直接返回
                                    dismiss()
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Image(systemName: "g.circle.fill")
                                .font(.title3)
                            Text("使用 Google 登入")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.white)
                        .foregroundColor(.black)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                    }
                }
                .padding(.horizontal, 32)

                // 錯誤訊息
                if let errorMessage = authManager.errorMessage, !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Spacer()
            }
        }
        .navigationTitle("登入 / 註冊")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(authManager.isLoading)
        .overlay {
            if authManager.isLoading {
                ZStack {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()

                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)
                }
            }
        }
        // 新用戶：全屏顯示個人資料設定
        .fullScreenCover(isPresented: $showProfileSetup) {
            NavigationStack {
                ProfileEditView(isNewUser: true)
                    .environmentObject(authManager)
            }
            .interactiveDismissDisabled()
            .onDisappear {
                // ProfileEditView 完成後，也關閉 SignInView
                if authManager.isLoggedIn &&
                   !(authManager.currentUser?.name.trimmingCharacters(in: .whitespaces).isEmpty ?? true) {
                    dismiss()
                }
            }
        }
    }
}
