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
import FirebaseFunctions
import AuthenticationServices
import CryptoKit

@MainActor
class AuthenticationManager: NSObject, ObservableObject {

    // MARK: - Auth State
    enum AuthState: Equatable {
        case loading      // 初始載入中
        case guest        // 本機使用者（未登入）
        case needsSetup   // 已登入但需要設定 profile（name 為空）
        case ready        // 已登入且 profile 完整
    }

    // MARK: - Published Properties
    @Published var authState: AuthState = .loading
    @Published var currentUser: UserProfile?
    @Published var localProfileImage: UIImage?  // 暫存本地圖片，優先顯示
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showDeviceConflictAlert = false

    // MARK: - Dependencies
    private let userRepository = UserRepository()
    private var authStateListener: AuthStateDidChangeListenerHandle?

    private var currentNonce: String?

    // 標記正在執行登入流程，防止 authStateListener 提前干擾
    private var isSigningIn = false

    // MARK: - Device ID
    var currentDeviceId: String {
        UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
    }

    // MARK: - 登入狀態
    var isLoggedIn: Bool {
        currentUser != nil && currentUser?.accountStatus == .member
    }

    // MARK: - Init
    override init() {
        super.init()
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
                    self?.setupLocalGuest()
                }
            }
        }
    }

    // MARK: - 設定本機 Guest 狀態
    private func setupLocalGuest() {
        currentUser = UserProfile.createLocal()
        authState = .guest
    }

    // MARK: - 處理認證狀態變化
    private func handleAuthStateChanged(user: FirebaseAuth.User) async {
        // 如果正在設定 profile（needsSetup），不要干擾
        guard authState != .needsSetup else { return }
        // 登入流程進行中，由 handleSignInSuccess 統一負責，避免 Race Condition
        guard !isSigningIn else { return }

        // 如果記憶體中已經有這個用戶的資料，不需要重新從 Firestore 讀取
        // 這可以防止 Token 刷新時，Firestore 的舊資料覆蓋剛更新的本地資料
        if let current = currentUser, current.uid == user.uid {
            return
        }

        // 只有在沒有本地資料時才從 Firestore 讀取（例如 App 啟動時）
        do {
            if let userProfile = try await userRepository.getUser(uid: user.uid) {
                // 檢查 Pro 會員是否過期
                var profile = userProfile
                if profile.isProExpired {
                    profile.membership = .free
                    try await userRepository.updateMembership(uid: profile.uid, membership: .free, expiryDate: nil)
                }
                self.currentUser = profile
                updateAuthState()

                // App 啟動時，如果是 member 就設定會員等級 + 初始化同步環境
                if profile.accountStatus == .member {
                    SyncManager.shared.setMembership(profile.membership)
                    await SyncManager.shared.initializeSync()
                }
            } else {
                setupLocalGuest()
            }
        } catch {
            print("Error fetching user profile: \(error)")
            setupLocalGuest()
        }
    }

    // MARK: - 更新 AuthState
    private func updateAuthState() {
        guard let user = currentUser else {
            authState = .guest
            return
        }

        if user.accountStatus == .guest {
            authState = .guest
        } else if user.name.trimmingCharacters(in: .whitespaces).isEmpty {
            authState = .needsSetup
        } else {
            authState = .ready
        }
    }

    // MARK: - Google 登入
    func signInWithGoogle() async {
        isSigningIn = true
        isLoading = true
        errorMessage = nil

        do {
            guard let credential = try await getGoogleCredential() else {
                isLoading = false
                isSigningIn = false
                return
            }

            let result = try await Auth.auth().signIn(with: credential)
            await handleSignInSuccess(user: result.user, provider: .google)
            isLoading = false
            isSigningIn = false
        } catch {
            isLoading = false
            isSigningIn = false
            errorMessage = getErrorMessage(from: error)
            print("Google sign in error: \(error)")
        }
    }

    // MARK: - Apple 登入
    func signInWithApple() {
        isSigningIn = true
        isLoading = true
        errorMessage = nil

        let nonce = randomNonceString()
        currentNonce = nonce

        let appleIDProvider = ASAuthorizationAppleIDProvider()
        let request = appleIDProvider.createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)

        let authorizationController = ASAuthorizationController(authorizationRequests: [request])
        authorizationController.delegate = self
        authorizationController.presentationContextProvider = self
        authorizationController.performRequests()
    }

    // MARK: - 處理 Apple 登入結果
    private func handleAppleSignIn(credential: ASAuthorizationAppleIDCredential) async {
        guard let nonce = currentNonce else {
            errorMessage = "無效的登入狀態"
            isLoading = false
            return
        }

        guard let appleIDToken = credential.identityToken,
              let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
            errorMessage = "無法取得 Apple Token"
            isLoading = false
            return
        }

        let firebaseCredential = OAuthProvider.appleCredential(
            withIDToken: idTokenString,
            rawNonce: nonce,
            fullName: credential.fullName
        )

        do {
            let result = try await Auth.auth().signIn(with: firebaseCredential)

            // Exchange authorization code for refresh token (stored server-side for revocation)
            if let authorizationCode = credential.authorizationCode,
               let authCodeString = String(data: authorizationCode, encoding: .utf8) {
                await exchangeAppleToken(authorizationCode: authCodeString)
            }

            await handleSignInSuccess(user: result.user, provider: .apple)
            isLoading = false
            isSigningIn = false
        } catch {
            isLoading = false
            isSigningIn = false
            errorMessage = getErrorMessage(from: error)
            print("Apple sign in error: \(error)")
        }
    }

    // MARK: - 交換 Apple Token（存入後端供日後 Revoke）
    private func exchangeAppleToken(authorizationCode: String) async {
        do {
            let functions = Functions.functions()
            _ = try await functions.httpsCallable("exchangeAppleToken").call(["authorizationCode": authorizationCode])
            print("get AppleToken")
        } catch {
            // Non-fatal：token 交換失敗不中斷登入流程
            print("exchangeAppleToken error: \(error)")
        }
    }

    // MARK: - 生成隨機 Nonce
    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        if errorCode != errSecSuccess {
            fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)")
        }

        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        let nonce = randomBytes.map { byte in
            charset[Int(byte) % charset.count]
        }
        return String(nonce)
    }

    // MARK: - SHA256 Hash
    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        let hashString = hashedData.compactMap {
            String(format: "%02x", $0)
        }.joined()
        return hashString
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

    // MARK: - 處理登入成功
    private func handleSignInSuccess(user: FirebaseAuth.User, provider: UserProfile.AuthProvider) async {
        do {
            // 1. 檢查本地是否有 LocalUser 資料
            let localHasData = SyncManager.shared.hasLocalData(for: UserProfile.guestUserId)

            // 2. 檢查雲端是否有資料
            let cloudHasData = await SyncManager.shared.hasCloudData(userId: user.uid)

            // 3. 建立 / 更新 UserProfile
            if let profile = try await userRepository.getUser(uid: user.uid) {
                self.currentUser = profile
                // Pro 會員允許多裝置同時登入，不覆蓋 deviceId
                if profile.membership == .free {
                    try await userRepository.updateDeviceId(uid: user.uid, deviceId: currentDeviceId)
                }
            } else {
                let email = user.email ?? ""
                let newProfile = UserProfile(
                    uid: user.uid,
                    email: email,
                    name: "",
                    photoURL: nil,
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

            // 4. 如果本地有 LocalUser 資料，遷移 userId
            if localHasData {
                SyncManager.shared.updateAllUserIds(from: UserProfile.guestUserId, to: user.uid)
            }

            // 5. 設定會員等級到 SyncManager
            if let membership = currentUser?.membership {
                SyncManager.shared.setMembership(membership)
            }

            // 6. 初始化同步環境
            await SyncManager.shared.initializeSync()

            // 7. 情境處理（所有情況自動合併，無需用戶選擇）
            if localHasData {
                // 本地有資料 → 先上傳
                await SyncManager.shared.fullUploadAllData()
                if cloudHasData {
                    // 兩邊都有 → 上傳後再下載雲端資料完成合併
                    await SyncManager.shared.performFullSync()
                }
            } else if cloudHasData {
                // 只有雲端 → 下載
                await SyncManager.shared.performFullSync()
            }
            // 兩邊都沒有 → 不需額外操作

            updateAuthState()
        } catch {
            print("Error handling sign in success: \(error)")
        }
    }

    // MARK: - 刪除帳號
    func deleteAccount() async {
        guard Auth.auth().currentUser != nil else { return }
        isLoading = true
        errorMessage = nil

        do {
            // Cloud Function 負責：Apple token revoke、Firestore 清除、Storage 清除、Auth 刪除
            let functions = Functions.functions()
            _ = try await functions.httpsCallable("deleteAccount").call()

            // 停止同步 + 清除本地資料
            SyncManager.shared.resetSync()
            SyncManager.shared.clearAllLocalData()
            localProfileImage = nil
            errorMessage = nil

            // 主動登出 + 重設狀態（Server 已刪除 Auth 帳號，client 需主動清除）
            try? Auth.auth().signOut()
            GIDSignIn.sharedInstance.signOut()
            setupLocalGuest()
        } catch {
            errorMessage = error.localizedDescription
            print("Delete account error: \(error)")
        }

        isLoading = false
    }

    // MARK: - 登出
    func signOut() {
        do {
            // 停止監聽並重置同步狀態
            SyncManager.shared.resetSync()
            // 清除所有本地資料
            SyncManager.shared.clearAllLocalData()

            try Auth.auth().signOut()
            GIDSignIn.sharedInstance.signOut()
            localProfileImage = nil
            errorMessage = nil

            // 重設為本機 Guest 狀態
            setupLocalGuest()
        } catch {
            errorMessage = error.localizedDescription
            print("Sign out error: \(error)")
        }
    }

    // MARK: - 檢查 Device ID（防止多處登入，僅限 Free 會員）
    func checkDeviceId() async {
        guard let user = currentUser, user.accountStatus == .member else { return }
        // Pro 會員允許多裝置同時登入，跳過衝突檢查
        guard user.membership == .free else { return }

        do {
            if let cloudProfile = try await userRepository.getUser(uid: user.uid) {
                if let cloudDeviceId = cloudProfile.currentDeviceId,
                   cloudDeviceId != currentDeviceId {
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
    func updateProfile(name: String?, photoURL: String?, localImage: UIImage? = nil) async {
        guard var user = currentUser else { return }

        do {
            try await userRepository.updateProfile(uid: user.uid, name: name, photoURL: photoURL)

            if let name = name {
                user.name = name
            }
            if let photoURL = photoURL {
                user.photoURL = photoURL
            }
            self.currentUser = user

            if let localImage = localImage {
                self.localProfileImage = localImage
            }

            updateAuthState()
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

// MARK: - ASAuthorizationControllerDelegate
extension AuthenticationManager: ASAuthorizationControllerDelegate {

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
            Task { @MainActor in
                await handleAppleSignIn(credential: appleIDCredential)
            }
        }
    }

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        Task { @MainActor in
            isLoading = false
            isSigningIn = false

            if let authError = error as? ASAuthorizationError,
               authError.code == .canceled {
                return
            }

            errorMessage = error.localizedDescription
            print("Apple Sign In error: \(error)")
        }
    }
}

// MARK: - ASAuthorizationControllerPresentationContextProviding
extension AuthenticationManager: ASAuthorizationControllerPresentationContextProviding {

    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            return UIWindow()
        }
        return window
    }
}
