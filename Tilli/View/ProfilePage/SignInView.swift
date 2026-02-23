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
                    // Apple 登入按鈕
                    Button {
                        authManager.signInWithApple()
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

                    // Google 登入按鈕
                    Button {
                        Task {
                            await authManager.signInWithGoogle()
                            // 登入成功後直接 dismiss
                            // ContentView 會根據 authState 自動顯示 ProfileEditView
                            if authManager.errorMessage == nil &&
                               (authManager.authState == .needsSetup || authManager.authState == .ready) {
                                dismiss()
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
        .onChange(of: authManager.authState) { newState in
            // Apple Sign In 透過 delegate 回傳，需要監聽 authState 變化來 dismiss
            if newState == .needsSetup || newState == .ready {
                dismiss()
            }
        }
        .alert("偵測到資料衝突", isPresented: $authManager.showDataConflictAlert) {
            Button("使用雲端資料", role: .destructive) {
                authManager.resolveConflictUseCloud()
            }
            Button("使用本地資料") {
                authManager.resolveConflictUseLocal()
            }
            Button("取消登入", role: .cancel) {
                authManager.resolveConflictCancel()
            }
        } message: {
            Text("本地有未同步的資料，登入帳號也有雲端資料。\n請選擇要保留哪份資料。")
        }
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
    }
}
