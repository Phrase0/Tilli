# 刪除帳號流程說明

## 架構概覽

刪除帳號由 **iOS client** 觸發，核心邏輯全部在 **Firebase Cloud Function（server 端）** 執行。

```
iOS App（deleteAccount）
  │
  ├─ 1. 呼叫 Cloud Function: deleteAccount
  │
  └─ Cloud Function
       ├─ 驗證 Firebase Auth token
       ├─ [Apple] Revoke refresh_token（best effort）
       ├─ 刪除 Firestore 所有資料
       ├─ 刪除 Storage 所有圖片
       └─ 刪除 Firebase Auth 帳號
```

---

## 為什麼在 Server 端執行

| 原因 | 說明 |
|------|------|
| Apple token revoke | Apple 規定必須從 server 端撤銷，client 無法直接做 |
| 刪除 Firebase Auth 帳號 | client 端 `deleteUser()` 需要「近期驗證」，Admin SDK 不需要 |
| 資料完整性 | 確保 Firestore、Storage、Auth 帳號一起清除，不留孤立資料 |

---

## 前置流程：Apple Token 備存

Apple Sign In 完成後，iOS 會立即呼叫 `exchangeAppleToken` function。

**原因**：Apple 的 `authorizationCode` 只能使用一次，且有效期約 5 分鐘。必須在登入當下立刻換成 `refresh_token` 存起來，供日後刪帳號時 revoke 使用。

```
Apple Sign In 完成
  → iOS 呼叫 exchangeAppleToken(authorizationCode)
  → Function 打 Apple API 換取 refresh_token
  → 存入 Firestore: users/{uid}/private/appleToken
```

---

## 刪除帳號詳細流程

### Step 1｜iOS 端（AuthenticationManager.swift）

```
用戶確認刪除
  → deleteAccount() 被呼叫
  → 確認 currentUser != nil
  → 呼叫 Cloud Function: deleteAccount
  → 成功後：
      resetSync()
      clearAllLocalData()
      Auth.auth().signOut()        ← 主動清除 client auth 狀態
      GIDSignIn.signOut()          ← 清除 Google Sign In 狀態
      setupLocalGuest()            ← 切回未登入頁
```

> **注意**：server 端刪除 Auth 帳號後，client 的 `authStateListener` 不一定會即時觸發，
> 因此必須主動呼叫 `signOut()` + `setupLocalGuest()`，不能依賴 listener 自動處理。

### Step 2｜Cloud Function 端（functions/src/index.ts）

**1. 驗證身份**
```
request.auth 為 null → 直接拒絕（UNAUTHENTICATED）
```

**2. 取得 provider**
```
讀取 Firestore: users/{uid}.provider
判斷是 "apple" 或 "google"
```

**3. Apple Token Revoke（僅 Apple 用戶）**
```
讀取 Firestore: users/{uid}/private/appleToken
取得 refresh_token
→ 建立 Apple JWT client secret（用 Secret Manager 中的私鑰，5 分鐘有效）
→ 打 Apple API: POST https://appleid.apple.com/auth/revoke
→ 失敗不中斷流程（best effort）
```

**4. 刪除 Firestore 資料**
```
刪除子集合（每批最多 450 筆，避免超過 Firestore batch 上限 500）：
  - sessions
  - categories
  - products
  - inventoryChanges
  - transactions
  - qrCodes
  - private（syncState、appleToken）
刪除主文件：users/{uid}
```

**5. 刪除 Storage 圖片**
```
刪除 prefix: users/{uid}/ 下所有檔案
```

**6. 刪除 Firebase Auth 帳號**
```
admin.auth().deleteUser(uid)
```

---

## Apple Token Revoke 的合規性

Apple App Store Guidelines 5.1.1 要求：使用 Sign in with Apple 的 app，刪除帳號時必須 revoke token。

| 情況 | Revoke 結果 | 帳號刪除 |
|------|------------|---------|
| refresh_token 有效 | 成功 ✅ | 完整刪除 ✅ |
| refresh_token 過期 | 失敗（被 catch 吞掉） | 完整刪除 ✅ |
| private/appleToken 不存在 | 跳過 | 完整刪除 ✅ |
| Google 用戶 | 跳過（不需要） | 完整刪除 ✅ |

Revoke 採 **best effort** 設計：失敗不中斷後續流程。

Token 過期時，通常代表用戶已在 Apple 設定中手動撤銷，視同 revoke 已完成，對合規無實質影響。

---

## Cloud Run IAM 設定說明

`deleteAccount` function 設定 `invoker: "public"`，這不代表「沒有安全性」。

實際上有兩層驗證：

| 層級 | 負責 | 驗證方式 |
|------|------|---------|
| Cloud Run IAM（`invoker: "public"`） | 允許 iOS client 到達 endpoint | 讓請求通過 |
| Firebase callable（`request.auth`） | 確認用戶已登入 | Firebase ID token |

iOS Firebase SDK 送出的是 Firebase Auth token，不是 GCP IAM 憑證，這是兩個不同的系統。若 Cloud Run 設為需要 GCP IAM 驗證，Firebase SDK 的 token 會被 401 擋住，永遠無法到達 function 邏輯。

---

## 相關檔案

| 檔案 | 說明 |
|------|------|
| `functions/src/index.ts` | Cloud Function 實作（exchangeAppleToken、deleteAccount） |
| `Tilli/Data/Repositories/AuthenticationManager.swift` | iOS 端呼叫邏輯（deleteAccount、signOut） |
| `Tilli/View/ProfilePage/ProfileView.swift` | 刪除帳號 UI 觸發點 |
