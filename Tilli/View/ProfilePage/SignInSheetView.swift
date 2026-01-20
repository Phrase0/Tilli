//
//  SignInSheet.swift
//  Tilli
//
//  Created by Peiyun on 2025/1/20.
//

import SwiftUI

struct SignInSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authManager: AuthenticationManager

    // MARK: - Email 登入表單狀態
    @State private var showEmailForm = false
    @State private var email = ""
    @State private var password = ""
    @FocusState private var focusedField: Field?

    enum Field {
        case email, password
    }

    var body: some View {
        NavigationStack {
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

                    // 登入區域
                    VStack(spacing: 16) {
                        if showEmailForm {
                            // Email 輸入表單
                            emailFormView
                        } else {
                            // 登入按鈕
                            loginButtonsView
                        }
                    }
                    .padding(.horizontal, 32)

                    // 錯誤訊息
                    if let errorMessage = authManager.errorMessage {
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
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        if showEmailForm {
                            // 返回登入選項
                            withAnimation {
                                showEmailForm = false
                                email = ""
                                password = ""
                                authManager.errorMessage = nil
                            }
                        } else {
                            dismiss()
                        }
                    } label: {
                        Image(systemName: showEmailForm ? "chevron.left" : "xmark")
                            .font(.body)
                            .foregroundColor(.primary)
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
        .interactiveDismissDisabled(authManager.isLoading)
    }

    // MARK: - 登入按鈕區
    private var loginButtonsView: some View {
        VStack(spacing: 16) {
            // Email 登入按鈕
            Button {
                withAnimation {
                    showEmailForm = true
                }
            } label: {
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

            // Apple 登入按鈕（待實作）
            Button {
                // TODO: 實作 Apple Sign In
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

            // Google 登入按鈕（待實作）
            Button {
                // TODO: 實作 Google Sign In
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
            .disabled(true)
            .opacity(0.5)
        }
    }

    // MARK: - Email 輸入表單
    private var emailFormView: some View {
        VStack(spacing: 16) {
            // Email 輸入框
            VStack(alignment: .leading, spacing: 8) {
                Text("Email")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                TextField("請輸入 Email", text: $email)
                    .textFieldStyle(.plain)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                    .padding(16)
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
                    .focused($focusedField, equals: .email)
            }

            // Password 輸入框
            VStack(alignment: .leading, spacing: 8) {
                Text("密碼")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                SecureField("請輸入密碼（至少 6 個字元）", text: $password)
                    .textFieldStyle(.plain)
                    .textContentType(.password)
                    .padding(16)
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
                    .focused($focusedField, equals: .password)
            }

            // 登入按鈕
            Button {
                focusedField = nil
                Task {
                    await authManager.signInWithEmail(email: email, password: password)
                    if authManager.errorMessage == nil {
                        dismiss()
                    }
                }
            } label: {
                Text("登入 / 註冊")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(isFormValid ? Color.blue : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .disabled(!isFormValid)

            // 提示文字
            Text("如果帳號不存在，將會自動為您註冊")
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - 表單驗證
    private var isFormValid: Bool {
        !email.isEmpty && email.contains("@") && password.count >= 6
    }
}
