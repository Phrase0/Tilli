# Cloud Functions 說明

涵蓋 `functions/src/index.ts` 中的兩個 Firebase Cloud Function：
`exchangeAppleToken`、`deleteAccount`

---

## 部署完整流程（從零開始）

> 前提：Firebase project 已存在，`firebase.json` / `.firebaserc` 已設定好。
> 這份流程記錄「如何在專案中加入 Cloud Functions」的完整步驟。

---

### Step 1：前置安裝

```bash
# 安裝 Node.js 24（建議用 nvm 管理版本）
nvm install 24
nvm use 24

# 安裝 Firebase CLI（全域）
npm install -g firebase-tools

# 登入 Firebase
firebase login
```

確認登入的帳號有 Firebase project 的 Owner 或 Editor 權限。

---

### Step 2：取得 Apple 憑證

四個 secret 的值都從 **Apple Developer Console** 取得：

#### Team ID
Apple Developer Console → 右上角帳號名稱 → Membership → **Team ID**（10 碼英數）

#### Bundle ID
Apple Developer Console → Certificates, Identifiers & Profiles → Identifiers → 選擇 App → **Bundle ID**（例：`com.company.appname`）

#### Key ID 和 Private Key（.p8 檔案）
1. Certificates, Identifiers & Profiles → **Keys** → 點「+」新增 key
2. 勾選 **Sign in with Apple** → Configure → 選擇對應的 App ID → Save
3. 填寫 Key Name → Continue → Register
4. 記下頁面上的 **Key ID**（10 碼英數）
5. 點 **Download** 下載 `.p8` 檔案

> ⚠️ `.p8` 檔案**只能下載一次**，下載後立刻存到安全的地方。
> 若遺失，只能刪掉舊 key 重新建立，並重新設定所有 secret。

`.p8` 檔案內容長這樣：
```
-----BEGIN PRIVATE KEY-----
MIGTAgEAMBMGet5qGSM49AgEGCCfjdoM49AwEHBHkwdwIBAQQg...（多行 base64）
-----END PRIVATE KEY-----
```

---

### Step 3：`firebase init functions`

在**專案根目錄**（`firebase.json` 所在的位置）執行：

```bash
firebase init functions
```

互動式問題的選擇：

| 問題 | 選擇 |
|------|------|
| Which Firebase project? | 選擇已存在的 project（`tilli-31b3f`） |
| What language? | **TypeScript** |
| Use ESLint? | **Yes** |
| Install dependencies with npm now? | **Yes** |

完成後會產生：
```
functions/
  src/
    index.ts       ← 主要撰寫 function 的地方
  .eslintrc.js
  package.json
  tsconfig.json
  tsconfig.dev.json
  .gitignore
```

---

### Step 4：設定 `functions/package.json`

確認 `engines.node` 版本與本地 Node 版本一致：

```json
{
  "engines": {
    "node": "24"
  },
  "dependencies": {
    "firebase-admin": "^13.6.0",
    "firebase-functions": "^7.0.0",
    "jsonwebtoken": "^9.0.3"
  },
  "devDependencies": {
    "@types/jsonwebtoken": "^9.0.10",
    ...
  }
}
```

安裝 `jsonwebtoken`（Apple JWT 簽署用）：

```bash
cd functions
npm install jsonwebtoken
npm install --save-dev @types/jsonwebtoken
cd ..
```

---

### Step 5：撰寫 `functions/src/index.ts`

將完整的 function 程式碼貼入 `functions/src/index.ts`。
程式碼邏輯說明見本文後半段。

---

### Step 6：設定 Secret Manager

四個 secret 全部用 `printf | firebase functions:secrets:set` 方式輸入，
**避免互動輸入時 Enter 被解讀為結束符號**。

```bash
# APPLE_TEAM_ID（10 碼，例：TEAMID1234）
printf 'TEAMID1234' | firebase functions:secrets:set APPLE_TEAM_ID

# APPLE_KEY_ID（10 碼，例：KEYID12345）
printf 'KEYID12345' | firebase functions:secrets:set APPLE_KEY_ID

# APPLE_BUNDLE_ID
printf 'com.company.appname' | firebase functions:secrets:set APPLE_BUNDLE_ID

# APPLE_PRIVATE_KEY（.p8 檔案的完整內容，用 cat 讀入）
cat /path/to/AuthKey_KEYID12345.p8 | firebase functions:secrets:set APPLE_PRIVATE_KEY
```

驗證四個 secret 都存入正確：
```bash
firebase functions:secrets:access APPLE_TEAM_ID      # 應顯示 10 碼 Team ID
firebase functions:secrets:access APPLE_KEY_ID       # 應顯示 10 碼 Key ID
firebase functions:secrets:access APPLE_BUNDLE_ID    # 應顯示 Bundle ID
firebase functions:secrets:access APPLE_PRIVATE_KEY  # 應顯示完整 PEM（5 行）
```

> `APPLE_PRIVATE_KEY` 正確格式：
> ```
> -----BEGIN PRIVATE KEY-----
> MIGTAgEA...（base64，每行 64 字元）
> -----END PRIVATE KEY-----
> ```

---

### Step 7：部署

```bash
# 從專案根目錄執行
firebase deploy --only functions
```

部署流程會自動執行：
1. ESLint 檢查（`npm run lint`）
2. TypeScript 編譯（`npm run build`，輸出到 `functions/lib/`）
3. 上傳到 Cloud Functions

部署成功後終端機會顯示：
```
✔  functions[exchangeAppleToken]: Successful
✔  functions[deleteAccount]: Successful
```

---

### Step 8：確認部署成功

**Firebase Console** → 選擇 project → **Functions** → 確認兩個 function 出現且狀態正常。

**Cloud Run Console**（Functions v2 底層是 Cloud Run）→ 確認每個 function 的 IAM 有 `allUsers` 的 `Cloud Run Invoker` 角色。

> 若 IAM 沒有自動設定，手動新增：
> Cloud Run → 選擇 function → Permissions → Add Principal → `allUsers` → Role: `Cloud Run Invoker`

---

### Step 9：後續修改與重新部署

修改 `functions/src/index.ts` 後，重新部署：

```bash
firebase deploy --only functions
```

只更新單一 function：
```bash
firebase deploy --only functions:exchangeAppleToken
firebase deploy --only functions:deleteAccount
```

---

### 常見錯誤

#### `Secret Manager Secret Accessor` 權限不足
```
Error: Could not access secret APPLE_PRIVATE_KEY
```
解法：GCP Console → IAM → 找到 function 的 Service Account（`project-id@appspot.gserviceaccount.com`）→ 新增 `Secret Manager Secret Accessor` 角色。

通常 Firebase 會自動授權，若沒有就手動加。

#### Apple token exchange 失敗
```
Apple token exchange failed: invalid_client
```
常見原因：
- `APPLE_PRIVATE_KEY` 格式錯誤（PEM 頭尾缺失或換行問題）
- `APPLE_BUNDLE_ID` 與 Key 設定的 App ID 不符
- `.p8` Key 已被 Apple 撤銷

解法：重新用 `cat` 方式設定 `APPLE_PRIVATE_KEY`，再用 `firebase functions:secrets:access` 確認格式。

#### ESLint 報錯導致部署失敗
```
error  Missing return type on function
```
解法：在 `functions/` 目錄執行 `npm run lint` 先在本地確認，修好後再部署。

#### TypeScript 編譯失敗
```
error TS2304: Cannot find name 'xxx'
```
解法：確認 `@types/jsonwebtoken` 已安裝，或執行 `npm install` 補安裝相依套件。

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
