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
import AuthenticationServices
import CryptoKit

@MainActor
class AuthenticationManager: NSObject, ObservableObject {

    // MARK: - Auth State
    enum AuthState: Equatable {
        case loading      // Firebase Auth 還在載入
        case guest        // 匿名用戶
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
                    self?.currentUser = nil
                    self?.authState = .guest
                }
            }
        }
    }

    // MARK: - 處理認證狀態變化
    private func handleAuthStateChanged(user: FirebaseAuth.User) async {
        // 如果正在設定 profile（needsSetup），不要干擾
        guard authState != .needsSetup else { return }

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
                // 更新 authState
                updateAuthState()

                // App 啟動時，如果是 member 就設定會員等級 + 初始化同步環境
                if profile.accountStatus == .member {
                    SyncManager.shared.setMembership(profile.membership)
                    await SyncManager.shared.initializeSync()
                }
            } else {
                // 有 Firebase Auth 用戶但沒有 UserProfile（可能是匿名用戶首次）
                self.authState = .guest
            }
        } catch {
            print("Error fetching user profile: \(error)")
            self.authState = .guest
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

    // MARK: - 自動匿名登入
    func signInAnonymously() async {
        // 如果已經有登入的用戶，不要重新匿名登入
        guard Auth.auth().currentUser == nil else {
            return
        }

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
            updateAuthState()
        } catch {
            isLoading = false
            authState = .guest
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

            // 登入前先捕捉匿名 UID（登入後 Auth.currentUser 就變成正式帳號）
            let anonymousUID = Auth.auth().currentUser?.isAnonymous == true
                ? Auth.auth().currentUser?.uid
                : nil

            guard let currentAuthUser = Auth.auth().currentUser, currentAuthUser.isAnonymous else {
                // 如果不是匿名用戶，直接登入
                let result = try await Auth.auth().signIn(with: credential)
                await handleSignInSuccess(user: result.user, provider: .google, anonymousUID: nil)
                isLoading = false
                return
            }

            // 嘗試 Link 匿名帳號到 Google（Link 成功一定是新帳號）
            do {
                let result = try await currentAuthUser.link(with: credential)
                await handleLinkSuccess(user: result.user, provider: .google, anonymousUID: anonymousUID)
                isLoading = false
            } catch let error as NSError {
                if error.code == AuthErrorCode.credentialAlreadyInUse.rawValue ||
                   error.code == AuthErrorCode.providerAlreadyLinked.rawValue {
                    // Credential 已被使用，刪除匿名帳號後登入
                    let anonymousUid = Auth.auth().currentUser?.uid

                    // 獨立 try-catch：匿名帳號清理失敗不影響後續登入流程
                    do {
                        try await Auth.auth().currentUser?.delete()
                    } catch {
                        print("⚠️ 匿名帳號刪除失敗（非致命）: \(error)")
                    }
                    if let uid = anonymousUid {
                        try? await userRepository.deleteUser(uid: uid)
                    }

                    // 優先使用 error 提供的 updatedCredential，避免 token 已消耗問題
                    let credentialToUse = error.userInfo[AuthErrorUserInfoUpdatedCredentialKey] as? AuthCredential
                        ?? credential

                    let result = try await Auth.auth().signIn(with: credentialToUse)
                    await handleSignInSuccess(user: result.user, provider: .google, anonymousUID: anonymousUID)
                    isLoading = false
                } else {
                    throw error
                }
            }
        } catch {
            isLoading = false
            errorMessage = getErrorMessage(from: error)
            print("Google sign in error: \(error)")
        }
    }

    // MARK: - Apple 登入
    func signInWithApple() {
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
            // 登入前先捕捉匿名 UID（登入後 Auth.currentUser 就變成正式帳號）
            let anonymousUID = Auth.auth().currentUser?.isAnonymous == true
                ? Auth.auth().currentUser?.uid
                : nil

            guard let currentAuthUser = Auth.auth().currentUser, currentAuthUser.isAnonymous else {
                // 如果不是匿名用戶，直接登入
                let result = try await Auth.auth().signIn(with: firebaseCredential)
                await handleSignInSuccess(user: result.user, provider: .apple, anonymousUID: nil)
                isLoading = false
                return
            }

            // 嘗試 Link 匿名帳號到 Apple（Link 成功一定是新帳號）
            do {
                let result = try await currentAuthUser.link(with: firebaseCredential)
                await handleLinkSuccess(user: result.user, provider: .apple, anonymousUID: anonymousUID)
                isLoading = false
            } catch let error as NSError {
                if error.code == AuthErrorCode.credentialAlreadyInUse.rawValue ||
                   error.code == AuthErrorCode.providerAlreadyLinked.rawValue {
                    // Credential 已被使用，刪除匿名帳號後登入
                    let anonymousUid = Auth.auth().currentUser?.uid

                    // 獨立 try-catch：匿名帳號清理失敗不影響後續登入流程
                    do {
                        try await Auth.auth().currentUser?.delete()
                    } catch {
                        print("⚠️ 匿名帳號刪除失敗（非致命）: \(error)")
                    }
                    if let uid = anonymousUid {
                        try? await userRepository.deleteUser(uid: uid)
                    }

                    // Apple token 是一次性的，link() 失敗後原始 credential 已被消耗
                    // 從 error 取出 updatedCredential（Firebase 在 credentialAlreadyInUse 時提供）
                    let credentialToUse = error.userInfo[AuthErrorUserInfoUpdatedCredentialKey] as? AuthCredential
                        ?? firebaseCredential

                    let result = try await Auth.auth().signIn(with: credentialToUse)
                    await handleSignInSuccess(user: result.user, provider: .apple, anonymousUID: anonymousUID)
                    isLoading = false
                } else {
                    throw error
                }
            }
        } catch {
            isLoading = false
            errorMessage = getErrorMessage(from: error)
            print("Apple sign in error: \(error)")
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

    // MARK: - 處理 Link 成功（情況 C：匿名 → 正式帳號，雲端無資料）
    private func handleLinkSuccess(user: FirebaseAuth.User, provider: UserProfile.AuthProvider, anonymousUID: String?) async {
        do {
            let email = user.email ?? ""

            // 升級現有的 UserProfile（姓名和頭貼留空，讓用戶自己填寫）
            try await userRepository.upgradeToMember(
                uid: user.uid,
                email: email,
                name: "",
                provider: provider
            )

            // 更新本地 currentUser
            if var profile = currentUser {
                profile.upgradeToMember(email: email, name: "", provider: provider)
                self.currentUser = profile
            }

            // 更新 deviceId
            try await userRepository.updateDeviceId(uid: user.uid, deviceId: currentDeviceId)

            // 更新本地所有資料的 userId（匿名 → 正式帳號 UID）
            if let oldUID = anonymousUID, !oldUID.isEmpty {
                SyncManager.shared.updateAllUserIds(from: oldUID, to: user.uid)
            }

            // 設定會員等級到 SyncManager（Link 成功 = 新帳號，預設 free）
            SyncManager.shared.setMembership(.free)

            // 初始化同步環境（設定新 userId + 根據 tier 決定是否啟動 Listener）
            await SyncManager.shared.initializeSync()

            // 全量上傳本地資料到 Firestore（新帳號，雲端尚無資料）
            await SyncManager.shared.fullUploadAllData()

            // 更新 authState（Link 成功 = 新帳號，需要設定 profile）
            authState = .needsSetup
        } catch {
            print("Error upgrading user: \(error)")
        }
    }

    // MARK: - 處理登入成功（情況 A/B/C/D 自動合併）
    private func handleSignInSuccess(user: FirebaseAuth.User, provider: UserProfile.AuthProvider, anonymousUID: String?) async {
        do {
            // 1. 在 Auth 切換前用匿名 UID 檢查本地資料
            let localHasData: Bool
            if let aUID = anonymousUID {
                localHasData = SyncManager.shared.hasLocalData(for: aUID)
            } else {
                localHasData = false
            }

            // 2. 檢查雲端是否有資料
            let cloudHasData = await SyncManager.shared.hasCloudData(userId: user.uid)

            // 3. 建立 / 更新 UserProfile
            if let profile = try await userRepository.getUser(uid: user.uid) {
                self.currentUser = profile
                try await userRepository.updateDeviceId(uid: user.uid, deviceId: currentDeviceId)
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

            // 4. 如果有本地匿名資料，先更新 userId
            if localHasData, let oldUID = anonymousUID, !oldUID.isEmpty {
                SyncManager.shared.updateAllUserIds(from: oldUID, to: user.uid)
            }

            // 5. 設定會員等級到 SyncManager
            if let membership = currentUser?.membership {
                SyncManager.shared.setMembership(membership)
            }

            // 6. 初始化同步環境
            await SyncManager.shared.initializeSync()

            // 7. 情境處理（所有情況自動合併，無需用戶選擇）
            if localHasData {
                // 情況 C/D：有本地資料 → 先上傳，再下載（UUID 唯一不衝突）
                await SyncManager.shared.fullUploadAllData()
                if cloudHasData {
                    // 情況 D：兩邊都有 → 上傳後再下載雲端資料完成合併
                    await SyncManager.shared.performFullSync()
                }
            } else if cloudHasData {
                // 情況 B：只有雲端 → 下載
                await SyncManager.shared.performFullSync()
            }
            // 情況 A：兩邊都沒 → 不需額外操作

            updateAuthState()
        } catch {
            print("Error handling sign in success: \(error)")
        }
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
            currentUser = nil
            localProfileImage = nil
            errorMessage = nil
            authState = .guest

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
    func updateProfile(name: String?, photoURL: String?, localImage: UIImage? = nil) async {
        guard var user = currentUser else { return }

        do {
            try await userRepository.updateProfile(uid: user.uid, name: name, photoURL: photoURL)

            // 更新本地 currentUser
            if let name = name {
                user.name = name
            }
            if let photoURL = photoURL {
                user.photoURL = photoURL
            }
            self.currentUser = user

            // 儲存本地圖片，讓 ProfileView 優先顯示
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

            // 使用者取消不顯示錯誤
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
