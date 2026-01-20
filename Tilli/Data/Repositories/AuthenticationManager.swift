//
//  AuthenticationManager.swift
//  Tilli
//
//  Created by Peiyun on 2025/1/20.
//

import Foundation
import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import GoogleSignIn
import FirebaseCore

@MainActor
class AuthenticationManager: ObservableObject {

    // MARK: - Published Properties
    @Published var currentUser: UserProfile?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showDeviceConflictAlert = false

    // MARK: - Dependencies
    private let userRepository = UserRepository()
    private var authStateListener: AuthStateDidChangeListenerHandle?

    // MARK: - Device ID
    var currentDeviceId: String {
        UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
    }

    // MARK: - 登入狀態
    var isLoggedIn: Bool {
        currentUser != nil && currentUser?.accountStatus == .member
    }

    var isGuest: Bool {
        currentUser?.accountStatus == .guest
    }

    // MARK: - Init
    init() {
        setupAuthStateListener()
    }

    deinit {
        if let listener = authStateListener {
            Auth.auth().removeStateDidChangeListener(listener)
        }
    }

    // MARK: - 監聽認證狀態變化
    private func setupAuthStateListener() {
        authStateListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                if let user = user {
                    await self?.handleAuthStateChanged(user: user)
                } else {
                    self?.currentUser = nil
                }
            }
        }
    }

    // MARK: - 處理認證狀態變化
    private func handleAuthStateChanged(user: FirebaseAuth.User) async {
        do {
            if let userProfile = try await userRepository.getUser(uid: user.uid) {
                // 檢查 Pro 會員是否過期
                var profile = userProfile
                if profile.isProExpired {
                    profile.membership = .free
                    try await userRepository.updateMembership(uid: profile.uid, membership: .free, expiryDate: nil)
                }
                self.currentUser = profile
            }
        } catch {
            print("Error fetching user profile: \(error)")
        }
    }

    // MARK: - 自動匿名登入
    func signInAnonymously() async {
        isLoading = true
        errorMessage = nil

        do {
            let result = try await Auth.auth().signInAnonymously()
            let uid = result.user.uid

            // 檢查是否已有 UserProfile
            let exists = try await userRepository.userExists(uid: uid)

            if !exists {
                // 建立新的 Guest UserProfile
                let guestUser = UserProfile.createGuest(uid: uid, deviceId: currentDeviceId)
                try await userRepository.createUser(guestUser)
                self.currentUser = guestUser
            } else {
                // 載入現有 UserProfile
                if let profile = try await userRepository.getUser(uid: uid) {
                    self.currentUser = profile
                    // 更新 deviceId
                    try await userRepository.updateDeviceId(uid: uid, deviceId: currentDeviceId)
                }
            }

            isLoading = false
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
            print("Anonymous sign in error: \(error)")
        }
    }

    // MARK: - Google 登入（Link 升級匿名帳號）
    func signInWithGoogle() async {
        isLoading = true
        errorMessage = nil

        do {
            // 取得 Google credential
            guard let credential = try await getGoogleCredential() else {
                isLoading = false
                return
            }

            guard let currentAuthUser = Auth.auth().currentUser, currentAuthUser.isAnonymous else {
                // 如果不是匿名用戶，直接登入
                let result = try await Auth.auth().signIn(with: credential)
                await handleSignInSuccess(user: result.user, provider: .google)
                return
            }

            // 嘗試 Link 匿名帳號到 Google
            do {
                let result = try await currentAuthUser.link(with: credential)
                await handleLinkSuccess(user: result.user, provider: .google)
            } catch let error as NSError {
                if error.code == AuthErrorCode.credentialAlreadyInUse.rawValue ||
                   error.code == AuthErrorCode.providerAlreadyLinked.rawValue {
                    // Credential 已被使用，刪除匿名帳號後登入
                    try await Auth.auth().currentUser?.delete()
                    let result = try await Auth.auth().signIn(with: credential)
                    await handleSignInSuccess(user: result.user, provider: .google)
                } else {
                    throw error
                }
            }

            isLoading = false
        } catch {
            isLoading = false
            errorMessage = getErrorMessage(from: error)
            print("Google sign in error: \(error)")
        }
    }

    // MARK: - 取得 Google Credential
    private func getGoogleCredential() async throws -> AuthCredential? {
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            errorMessage = "Firebase 設定錯誤"
            return nil
        }

        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config

        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            errorMessage = "無法取得視窗"
            return nil
        }

        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController)

        guard let idToken = result.user.idToken?.tokenString else {
            errorMessage = "無法取得 Google Token"
            return nil
        }

        let accessToken = result.user.accessToken.tokenString
        let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: accessToken)

        return credential
    }

    // MARK: - 處理 Link 成功
    private func handleLinkSuccess(user: FirebaseAuth.User, provider: UserProfile.AuthProvider) async {
        do {
            let email = user.email ?? ""
            let name = user.displayName ?? email.components(separatedBy: "@").first ?? "使用者"
            let photoURL = user.photoURL?.absoluteString

            // 升級現有的 UserProfile
            try await userRepository.upgradeToMember(
                uid: user.uid,
                email: email,
                name: name,
                provider: provider
            )

            // 更新照片 URL
            if let photoURL = photoURL {
                try await userRepository.updateProfile(uid: user.uid, name: nil, photoURL: photoURL)
            }

            // 更新本地 currentUser
            if var profile = currentUser {
                profile.upgradeToMember(email: email, name: name, provider: provider)
                profile.photoURL = photoURL
                self.currentUser = profile
            }

            // 更新 deviceId
            try await userRepository.updateDeviceId(uid: user.uid, deviceId: currentDeviceId)
        } catch {
            print("Error upgrading user: \(error)")
        }
    }

    // MARK: - 處理登入成功
    private func handleSignInSuccess(user: FirebaseAuth.User, provider: UserProfile.AuthProvider) async {
        do {
            if let profile = try await userRepository.getUser(uid: user.uid) {
                self.currentUser = profile
                // 更新 deviceId
                try await userRepository.updateDeviceId(uid: user.uid, deviceId: currentDeviceId)
            } else {
                // 如果沒有 UserProfile，建立一個新的
                let email = user.email ?? ""
                let name = user.displayName ?? email.components(separatedBy: "@").first ?? "使用者"
                let photoURL = user.photoURL?.absoluteString

                let newProfile = UserProfile(
                    uid: user.uid,
                    email: email,
                    name: name,
                    photoURL: photoURL,
                    provider: provider,
                    accountStatus: .member,
                    membership: .free,
                    expiryDate: nil,
                    createdAt: Date(),
                    currentDeviceId: currentDeviceId
                )
                try await userRepository.createUser(newProfile)
                self.currentUser = newProfile
            }

            isLoading = false
        } catch {
            print("Error handling sign in success: \(error)")
            isLoading = false
        }
    }

    // MARK: - 登出
    func signOut() {
        do {
            try Auth.auth().signOut()
            GIDSignIn.sharedInstance.signOut()
            currentUser = nil
            errorMessage = nil

            // 重新匿名登入
            Task {
                await signInAnonymously()
            }
        } catch {
            errorMessage = error.localizedDescription
            print("Sign out error: \(error)")
        }
    }

    // MARK: - 檢查 Device ID（防止多處登入）
    func checkDeviceId() async {
        guard let user = currentUser, user.accountStatus == .member else { return }

        do {
            if let cloudProfile = try await userRepository.getUser(uid: user.uid) {
                if let cloudDeviceId = cloudProfile.currentDeviceId,
                   cloudDeviceId != currentDeviceId {
                    // Device ID 不匹配，顯示衝突提示
                    showDeviceConflictAlert = true
                }
            }
        } catch {
            print("Error checking device ID: \(error)")
        }
    }

    // MARK: - 踢掉其他裝置（更新 Device ID）
    func kickOtherDevice() async {
        guard let user = currentUser else { return }

        do {
            try await userRepository.updateDeviceId(uid: user.uid, deviceId: currentDeviceId)
            showDeviceConflictAlert = false
        } catch {
            print("Error kicking other device: \(error)")
        }
    }

    // MARK: - 更新個人資料
    func updateProfile(name: String?, photoURL: String?) async {
        guard let user = currentUser else { return }

        do {
            try await userRepository.updateProfile(uid: user.uid, name: name, photoURL: photoURL)

            // 更新本地 currentUser
            if let name = name {
                currentUser?.name = name
            }
            if let photoURL = photoURL {
                currentUser?.photoURL = photoURL
            }
        } catch {
            print("Error updating profile: \(error)")
        }
    }

    // MARK: - 錯誤訊息轉換
    private func getErrorMessage(from error: Error) -> String {
        let nsError = error as NSError
        switch nsError.code {
        case AuthErrorCode.userNotFound.rawValue:
            return "找不到此帳號"
        case AuthErrorCode.networkError.rawValue:
            return "網路連線錯誤"
        case AuthErrorCode.userDisabled.rawValue:
            return "此帳號已被停用"
        case AuthErrorCode.operationNotAllowed.rawValue:
            return "此登入方式未啟用"
        case GIDSignInError.canceled.rawValue:
            return "" // 使用者取消，不顯示錯誤
        default:
            return error.localizedDescription
        }
    }
}
