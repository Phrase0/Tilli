# Session 刪除測試驗證

## 修改內容總結

### 1. CoreData 模型修改
- **變更前**: `CDSessionEntity.transactions` 使用 `deletionRule="Cascade"`
- **變更後**: `CDSessionEntity.transactions` 使用 `deletionRule="Nullify"`

### 2. SessionDataManager 修改
- 新增 `fetchTransactionsForSession(sessionId:)` 方法
- 修改 `fetchSessions()` 使用 sessionId 查詢交易記錄
- 修改 `fetchSession(by:)` 使用 sessionId 查詢交易記錄
- 更新 `deleteSession()` 註解說明

## 預期行為

### 刪除 Session 前
```
Session A (id: session-uuid-a)
├── Categories (會被刪除)
├── Products (會被刪除)  
└── Transactions (會保留)
    ├── Transaction 1 (session: session-uuid-a)
    └── Transaction 2 (session: session-uuid-a)
```

### 刪除 Session 後
```
Session A -> 已刪除

Transactions (保留在資料庫中)
├── Transaction 1 (sessionId: session-uuid-a, session: nil)
└── Transaction 2 (sessionId: session-uuid-a, session: nil)
```

## 測試案例

### ✅ 應該正常運作的功能
1. **交易歷史查詢**: `TransactionDataManager.fetchTransactions(forSessionId:)` 仍能查到交易
2. **分析統計**: 基於 sessionId 的統計查詢不受影響
3. **Session 列表**: 顯示時不會包含已刪除 Session 的交易
4. **CSV 匯出**: 歷史交易仍可正常匯出

### ❌ 需要注意的變化
1. **Session.transactions**: 刪除 Session 後，透過關聯查詢會返回空陣列
2. **Transaction.session**: 會變成 nil，但 sessionId 欄位保持原值

## 驗證步驟

1. **創建測試資料**
   - 建立 Session A 包含 2 個 Categories、5 個 Products
   - 進行 3 筆交易

2. **刪除前檢查**
   - 確認 Session A 有 3 筆交易
   - 確認 TransactionDataManager 能查詢到這些交易

3. **執行刪除**
   - 調用 `SessionDataManager.deleteSession(sessionA.id)`

4. **刪除後驗證**
   - ✅ Session A 不再出現在 sessions 列表
   - ✅ Categories 和 Products 已被刪除
   - ✅ 3 筆 Transaction 仍存在於資料庫
   - ✅ `TransactionDataManager.fetchTransactions(forSessionId: sessionA.id)` 仍返回 3 筆交易
   - ✅ 交易記錄的 sessionId 仍為 sessionA.id

## 結論

修改完成後，**交易記錄確實會被保留**，可以安全地實施批次刪除 Session 功能。