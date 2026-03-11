# Cloud Functions 說明

涵蓋 `functions/src/index.ts` 中的兩個 Firebase Cloud Function：
`exchangeAppleToken`、`deleteAccount`

---

## 架構概覽

```
iOS App
  ├─ Apple Sign In 完成 → exchangeAppleToken(authorizationCode)
  │     └─ Cloud Function
  │           ├─ 驗證 Firebase Auth token
  │           ├─ 打 Apple API 換取 refresh_token
  │           └─ 存入 Firestore: users/{uid}/private/appleToken
  │
  └─ 用戶確認刪除 → deleteAccount()
        └─ Cloud Function
              ├─ 驗證 Firebase Auth token
              ├─ [Apple] Revoke refresh_token（best effort）
              ├─ 刪除 Firestore 所有資料
              ├─ 刪除 Storage 所有圖片
              └─ 刪除 Firebase Auth 帳號
```

---

## Function 1：exchangeAppleToken

### 用途

Apple Sign In 完成後立即呼叫，將一次性的 `authorizationCode` 換成 `refresh_token`，
存入 Firestore 供日後刪帳號時 revoke 使用。

`authorizationCode` 只能使用一次，有效期約 5 分鐘，必須在登入當下立刻交換。

### 呼叫時機（iOS 端）

`AuthenticationManager.swift` 的 `handleAppleSignIn`：

```swift
let result = try await Auth.auth().signIn(with: firebaseCredential)
// ^ 先完成 Firebase Sign In，確保 request.auth 可用
if let authorizationCode = credential.authorizationCode,
   let authCodeString = String(data: authorizationCode, encoding: .utf8) {
    await exchangeAppleToken(authorizationCode: authCodeString)
    // Non-fatal：失敗不中斷登入流程
}
await handleSignInSuccess(user: result.user, provider: .apple)
```

### Cloud Function 邏輯

1. 驗證 `request.auth`（Firebase Auth token），不存在則拒絕
2. `buildAppleClientSecret()`：用 Secret Manager 的 private key 建立 Apple JWT（ES256，5 分鐘有效）
3. POST `https://appleid.apple.com/auth/token`，換取 `refresh_token`
4. 存入 `users/{uid}/private/appleToken`：`{ refreshToken, updatedAt }`

### Firestore 儲存位置

```
users/{uid}/private/appleToken
  ├─ refreshToken: string
  └─ updatedAt: Timestamp
```

---

## Function 2：deleteAccount

### 用途

Google / Apple 共用的帳號刪除流程，核心邏輯全在 server 端執行。

| 原因 | 說明 |
|------|------|
| Apple token revoke | Apple 規定必須從 server 端撤銷 |
| 刪除 Firebase Auth 帳號 | Admin SDK 不需要「近期驗證」，client 端 `deleteUser()` 需要 |
| 資料完整性 | 確保 Firestore、Storage、Auth 帳號一起清除 |

### iOS 端流程

```swift
// AuthenticationManager.swift - deleteAccount()
呼叫 Cloud Function: deleteAccount
成功後：
  SyncManager.shared.resetSync()
  SyncManager.shared.clearAllLocalData()
  Auth.auth().signOut()      // 主動清除，不依賴 authStateListener
  GIDSignIn.sharedInstance.signOut()
  setupLocalGuest()
```

> server 端刪除 Auth 帳號後，client 的 `authStateListener` 不一定即時觸發，
> 必須主動 signOut + setupLocalGuest，不能依賴 listener 自動處理。

### Cloud Function 邏輯

**1. 驗證身份**
`request.auth` 為 null → 拒絕（UNAUTHENTICATED）

**2. 取得 provider**
讀取 `Firestore: users/{uid}.provider`（值為 `"apple"` 或 `"google"`）

**3. Apple Token Revoke（僅 Apple 用戶）**
```
讀取 users/{uid}/private/appleToken.refreshToken
→ buildAppleClientSecret()
→ POST https://appleid.apple.com/auth/revoke
→ 失敗不中斷（best effort，catch 住繼續往下）
```

**4. 刪除 Firestore 資料**
```
子集合（每批最多 450 筆，避免超過 batch 上限 500）：
  sessions / categories / products / inventoryChanges / transactions / qrCodes
private 子集合（所有文件，包含 appleToken 等）
主文件 users/{uid}
```

**5. 刪除 Storage 圖片**
`users/{uid}/` prefix 下所有檔案（單筆失敗不影響其他）

**6. 刪除 Firebase Auth 帳號**
`admin.auth().deleteUser(uid)`

### Apple Token Revoke 合規性

Apple App Store Guidelines 5.1.1 要求：使用 Sign in with Apple 的 app，刪除帳號時必須 revoke token。

| 情況 | Revoke 結果 | 帳號刪除 |
|------|------------|---------|
| refresh_token 有效 | 成功 ✅ | 完整刪除 ✅ |
| refresh_token 過期 | 失敗（被 catch 吞掉） | 完整刪除 ✅ |
| private/appleToken 不存在 | 跳過 | 完整刪除 ✅ |
| Google 用戶 | 跳過 | 完整刪除 ✅ |

---

## buildAppleClientSecret 實作說明

`APPLE_PRIVATE_KEY` 從 Secret Manager 取出後，先正規化 PEM 格式再傳給 `jwt.sign`：

```typescript
// 處理兩種儲存格式：真正換行 或 \n 逸脫字元
let keyStr = APPLE_PRIVATE_KEY.value().replace(/\\n/g, "\n").trim();

// 重組標準 PEM：去掉所有空白 → 每 64 字元換行 → 補回 header/footer
const match = keyStr.match(/-----BEGIN ([A-Z ]+)-----\s*([\s\S]+?)\s*-----END \1-----/);
if (match) { /* 重組 */ }

jwt.sign({}, keyStr, { algorithm: "ES256", expiresIn: "5m", ... });
```

這樣無論 Secret Manager 存的是多行或單行格式都能正確處理。

---

## Cloud Run IAM 設定

兩個 function 都設定 `invoker: "public"`，這不代表沒有安全性：

| 層級 | 負責 | 驗證方式 |
|------|------|---------|
| Cloud Run IAM（`invoker: "public"`） | 讓 iOS client 到達 endpoint | 允許通過 |
| Firebase callable（`request.auth`） | 確認用戶已登入 | Firebase ID token |

iOS Firebase SDK 送的是 Firebase Auth token，不是 GCP IAM 憑證。若 Cloud Run 設為需要 GCP IAM 驗證，Firebase SDK 的 token 會被 401 擋住，永遠無法執行 function 邏輯。

---

## Secret Manager 設定方式

**正確做法**（用 pipe 避免互動輸入的重複問題）：

```bash
# APPLE_PRIVATE_KEY（多行，用 cat 或 printf）
printf '-----BEGIN PRIVATE KEY-----\nMIGT...\n-----END PRIVATE KEY-----\n' \
  | firebase functions:secrets:set APPLE_PRIVATE_KEY

# 其他單行 secret
printf 'com.company.app' | firebase functions:secrets:set APPLE_BUNDLE_ID
printf 'TEAMID1234' | firebase functions:secrets:set APPLE_TEAM_ID
printf 'KEYID12345' | firebase functions:secrets:set APPLE_KEY_ID
```

**驗證**：
```bash
firebase functions:secrets:access APPLE_PRIVATE_KEY   # 應顯示完整 5 行
firebase functions:secrets:access APPLE_BUNDLE_ID     # 應只顯示一次 bundle ID
```

> 用 `firebase functions:secrets:set` 互動輸入時，Enter 鍵會被解讀為「輸入結束」，
> 導致多行 key 只存第一行，或單行值被重複輸入兩次。

---

## 相關檔案

| 檔案 | 說明 |
|------|------|
| `functions/src/index.ts` | Cloud Function 實作 |
| `Tilli/Data/Repositories/AuthenticationManager.swift` | iOS 端呼叫邏輯 |
| `Tilli/View/ProfilePage/ProfileView.swift` | 刪除帳號 UI 觸發點 |
