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
    @Published var currentUser: UserProfileModel?
    @Published var localProfileImage: UIImage?  // 暫存本地圖片，優先顯示
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showDeviceConflictAlert = false
    @Published var kickOtherDeviceErrorMessage: String?
    @Published var deleteAccountBlockedMessage: String?

    // 登出前檢查「是否有資料尚未同步」用
    @Published var showSignOutDataLossWarning = false
    @Published var pendingUnsyncedCount = 0

    // MARK: - Dependencies
    private let userRepository = UserRepository()
    private var authStateListener: AuthStateDidChangeListenerHandle?

    private var currentNonce: String?

    // 標記正在執行登入流程，防止 authStateListener 提前干擾
    private var isSigningIn = false

    // 標記正在執行登出流程，防止使用者連點登出按鈕時 requestSignOut() 被重入
    // （重入會讓第二次呼叫跳過同步、直接清空本機資料，跟第一次呼叫還沒跑完的佇列處理互撞）
    private var isSigningOut = false

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
        currentUser = UserProfileModel.createLocal()
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
            guard let userProfile = try await userRepository.getUser(uid: user.uid) else {
                setupLocalGuest()
                return
            }

            // 檢查 Pro 會員是否過期
            var profile = userProfile
            if profile.isProExpired {
                profile.membership = .free
                try await userRepository.updateMembership(uid: profile.uid, membership: .free, expiryDate: nil)
            }

            // LWW：本地如果有還沒上傳成功的個人資料編輯，姓名/大頭貼用本地版本，
            // 不要被剛從 Firestore 抓回來的舊資料蓋掉（跟 FirestoreDownloader.saveProduct 同一套比較方式）
            let hasNewerLocalEdit: Bool
            if let local = userRepository.loadLocalUserProfile(uid: user.uid), local.updatedAt > profile.updatedAt {
                profile.name = local.name
                profile.photoURL = local.photoURL
                profile.updatedAt = local.updatedAt
                hasNewerLocalEdit = true
            } else {
                hasNewerLocalEdit = false
            }

            self.currentUser = profile
            userRepository.saveUserProfileLocally(profile, syncStatus: hasNewerLocalEdit ? .pending : .synced)
            updateAuthState()

            // TODO: [SYNC-PENDING] App 啟動且為 member 時：初始化同步、必要時補全量下載、
            // 重試本機未上傳的個人資料編輯（hasNewerLocalEdit）。
            // ⚠️ 重建時注意：離線時 getUser 失敗【不可】降級成 Guest，
            //    要讀本機 CDUserProfileEntity 快取維持登入狀態。見 SYNC_ARCHITECTURE_V2.md §9.1
            _ = hasNewerLocalEdit
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
        guard NetworkMonitor.shared.isConnected else {
            errorMessage = String.localized("authNetworkRequiredForSignIn")
            return
        }

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
        guard NetworkMonitor.shared.isConnected else {
            errorMessage = String.localized("authNetworkRequiredForSignIn")
            return
        }

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
    private func handleSignInSuccess(user: FirebaseAuth.User, provider: UserProfileModel.AuthProvider) async {
        do {
            // 1. 檢查本地是否有訪客資料（決定要不要歸戶）
            let localHasData = LocalDataManager.shared.hasLocalData(for: UserProfileModel.guestUserId)

            // TODO: [SYNC-PENDING] 2. 檢查雲端是否有資料。
            // ⚠️ 重建時要改成三態（true / false / unknown），
            //    unknown（離線、查詢失敗）時不可做任何破壞性動作。見 SYNC_ARCHITECTURE_V2.md §9.1

            // 3. 建立 / 更新 UserProfileModel
            if let profile = try await userRepository.getUser(uid: user.uid) {
                self.currentUser = profile
                // Pro 會員允許多裝置同時登入，不覆蓋 deviceId
                if profile.membership == .free {
                    try await userRepository.updateDeviceId(uid: user.uid, deviceId: currentDeviceId)
                }
            } else {
                let email = user.email ?? ""
                let newProfile = UserProfileModel(
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

            // 登入成功後立刻補寫本地快取，跟其他寫入 currentUser 的路徑（handleAuthStateChanged／updateProfile）一致，
            // 避免登出後 clearAllLocalData() 清空快取、下次登入這個 uid 在本機是空的
            if let user = currentUser {
                userRepository.saveUserProfileLocally(user, syncStatus: .synced)
            }

            // 4. 本機有訪客資料 → 歸戶到正式帳號（純本機操作）
            if localHasData {
                LocalDataManager.shared.updateAllUserIds(from: UserProfileModel.guestUserId, to: user.uid)
            }

            // TODO: [SYNC-PENDING] 5~7. 初始化同步環境並處理三種合併情境：
            //   本機有 + 雲端有 → 先上傳再下載
            //   只有本機       → 全量上傳（顯示進度條）
            //   只有雲端       → 全量下載
            // ⚠️ 重建時注意：上傳失敗的資料【不可】標記為 synced，
            //    且 cleanUp 不可在上傳有失敗時執行。見 SYNC_ARCHITECTURE_V2.md 附錄 A

            updateAuthState()
        } catch {
            print("Error handling sign in success: \(error)")
        }
    }

    // MARK: - 刪除帳號前檢查網路（給 UI 在跳出確認對話框之前呼叫）
    /// 離線時不可以刪除帳號；回傳 false 時 `deleteAccountBlockedMessage` 已經設定好通知內容。
    func canAttemptDeleteAccount() -> Bool {
        guard NetworkMonitor.shared.isConnected else {
            deleteAccountBlockedMessage = String.localized("authNetworkRequiredForDeleteAccount")
            return false
        }
        return true
    }

    // MARK: - 刪除帳號
    func deleteAccount() async {
        guard Auth.auth().currentUser != nil else { return }
        guard canAttemptDeleteAccount() else { return }
        isLoading = true
        errorMessage = nil

        do {
            // Cloud Function 負責：Apple token revoke、Firestore 清除、Storage 清除、Auth 刪除
            let functions = Functions.functions()
            _ = try await functions.httpsCallable("deleteAccount").call()

            // 清除本地資料（帳號已由 Cloud Function 刪除，雲端資料不存在）
            LocalDataManager.shared.clearAllLocalData()
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

    // MARK: - 登出入口
    /// 給 UI 呼叫的登出入口。
    ///
    /// TODO: [SYNC-PENDING] 重建同步後，這裡要：
    ///   1. 先把 outbox 推送完（顯示進度，**必須有上限**，例如 30 秒）
    ///   2. 未訂閱／推送未完成 → 詢問使用者「保留或刪除本機資料」，**不可靜默清除**
    /// ⚠️ 舊版用無上限的 while 迴圈等待，是登出無限轉圈的根因。
    ///    見 SYNC_ARCHITECTURE_V2.md §9.2、§9.6
    func requestSignOut() async {
        guard !isSigningOut else { return }
        isSigningOut = true
        defer { isSigningOut = false }

        signOut()
    }

    // MARK: - 登出
    func signOut() {
        do {
            // 清除所有本地資料
            // ⚠️ 重建同步後，這裡【不可】無條件清除 —— 見 requestSignOut 的 TODO
            LocalDataManager.shared.clearAllLocalData()
            localProfileImage = nil
            errorMessage = nil
            
            try Auth.auth().signOut()
            GIDSignIn.sharedInstance.signOut()
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
        kickOtherDeviceErrorMessage = nil

        // 原本的衝突 alert 一按按鈕就會關閉，這裡的錯誤要另外顯示，不能沿用同一個 alert
        guard NetworkMonitor.shared.isConnected else {
            kickOtherDeviceErrorMessage = String.localized("authKickOtherDeviceNoNetwork")
            showDeviceConflictAlert = true
            return
        }

        do {
            try await userRepository.updateDeviceId(uid: user.uid, deviceId: currentDeviceId)
            showDeviceConflictAlert = false
        } catch {
            print("Error kicking other device: \(error)")
            kickOtherDeviceErrorMessage = String.localized("authKickOtherDeviceFailed")
            showDeviceConflictAlert = true
        }
    }

    // MARK: - 更新個人資料（本地優先：一定成功，不管有沒有網路）
    func updateProfile(name: String?, image: UIImage? = nil) async {
        guard var user = currentUser else { return }

        // 只有這次真的換了新頭貼才需要重新上傳，跟商品的 imageChanged 邏輯一致，
        // 避免每次只改名字，也把同一張沒變過的頭貼重新上傳一次
        let imageChanged = image != nil

        if let name = name {
            user.name = name
        }
        if let image = image {
            user.image = image
            self.localProfileImage = image
        }
        user.updatedAt = Date()

        self.currentUser = user
        userRepository.saveUserProfileLocally(user, syncStatus: .pending)
        updateAuthState()

        // TODO: [SYNC-PENDING] 重建同步後在此 enqueue 個人資料（含頭貼上傳）
        _ = imageChanged
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
