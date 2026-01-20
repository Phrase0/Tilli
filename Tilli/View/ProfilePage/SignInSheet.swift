//
//  SignInSheet.swift
//  Tilli
//
//  Created by Peiyun on 2025/1/20.
//

import SwiftUI

struct SignInSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authManager: AuthenticationManager

    var body: some View {
        NavigationStack {
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
                    // Email 登入按鈕
                    Button(action: {
                        authManager.signInWithEmail(email: "test@example.com", password: "")
                        dismiss()
                    }) {
                        HStack {
                            Image(systemName: "envelope.fill")
                                .font(.title3)
                            Text("使用 Email 登入")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }

                    // Apple 登入按鈕
                    Button(action: {
                        authManager.signInWithApple()
                        dismiss()
                    }) {
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
                    Button(action: {
                        authManager.signInWithGoogle()
                        dismiss()
                    }) {
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

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("登入 / 註冊")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("關閉") {
                        dismiss()
                    }
                }
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
}
