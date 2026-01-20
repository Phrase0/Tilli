//
//  AuthenticationManager.swift
//  Tilli
//
//  Created by Peiyun on 2025/1/20.
//

import Foundation
import SwiftUI

class AuthenticationManager: ObservableObject {
    @Published var currentUser: User?
    @Published var isLoading = false
    @Published var errorMessage: String?

    // MARK: - 登入狀態
    var isLoggedIn: Bool {
        currentUser != nil
    }

    // MARK: - Email 登入（模擬）
    func signInWithEmail(email: String, password: String) {
        isLoading = true
        errorMessage = nil

        // TODO: 實際串接 Firebase Authentication
        // 目前模擬登入成功
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.currentUser = User(
                id: UUID().uuidString,
                name: "王小明",
                email: email,
                photoURL: nil,
                provider: .email
            )
            self?.isLoading = false
        }
    }

    // MARK: - Apple 登入（模擬）
    func signInWithApple() {
        isLoading = true
        errorMessage = nil

        // TODO: 實際串接 Apple Sign In
        // 目前模擬登入成功
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.currentUser = User(
                id: UUID().uuidString,
                name: "Apple 使用者",
                email: "apple@example.com",
                photoURL: nil,
                provider: .apple
            )
            self?.isLoading = false
        }
    }

    // MARK: - Google 登入（模擬）
    func signInWithGoogle() {
        isLoading = true
        errorMessage = nil

        // TODO: 實際串接 Google Sign In
        // 目前模擬登入成功
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.currentUser = User(
                id: UUID().uuidString,
                name: "Google 使用者",
                email: "google@example.com",
                photoURL: nil,
                provider: .google
            )
            self?.isLoading = false
        }
    }

    // MARK: - 登出
    func signOut() {
        // TODO: 實際串接 Firebase Authentication 登出
        currentUser = nil
        errorMessage = nil
    }
}
