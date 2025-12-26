//
//  AddSessionViewModel.swift
//  Tilli
//
//  Created by Peiyun on 2025/6/17.
//

import Foundation

class AddSessionViewModel: ObservableObject {
    @Published var sessionName: String
    @Published var sessionDate: Date
    @Published var selectedCurrency: String
    @Published var newCategory: String = ""
    @Published var categories: [CategoryModel]
    @Published var editingCategoryID: UUID?

    // 多日場次支援
    @Published var dateType: SessionDateType
    @Published var endDate: Date

    // 折扣相關狀態
    @Published var discounts: [DiscountModel] = []
    @Published var newDiscountValue: String = ""
    @Published var newDiscountType: DiscountType = .percentage

    // Alert 相關狀態
    @Published var showAlert = false
    @Published var alertMessage = ""
    @Published var categoryPendingDeletion: UUID?
    @Published var categoryPendingRestore: UUID?
    @Published var isDisableAction = false

    var editingSession: SessionModel?

    // 用於獲取最新狀態的 DataManager
    private var transactionDataManager: TransactionDataManager?
    private var productRepository: ProductRepository?

    // 判斷是否有交易記錄（用於決定是否可編輯幣別）
    var isEditingWithTransaction: Bool {
        return hasTransaction()
    }

    // 取得場次的交易筆數
    var transactionCount: Int {
        guard let sessionId = editingSession?.id,
              let transactionManager = transactionDataManager else {
            return 0
        }
        return transactionManager.fetchTransactions(forSessionId: sessionId).count
    }
    
    var sortedCategories: [CategoryModel] {
        categories.sorted(by: { $0.createdAt < $1.createdAt })
    }
    
    var activeSortedCategories: [CategoryModel] {
        categories.filter { !$0.isDisabled }.sorted(by: { $0.createdAt < $1.createdAt })
    }
    
    var disabledSortedCategories: [CategoryModel] {
        categories.filter { $0.isDisabled }.sorted(by: { $0.createdAt < $1.createdAt })
    }
    
    var selectedCategory: CategoryModel? {
        sortedCategories.first(where: { $0.id == editingCategoryID })
    }

    // 計算多日場次的天數
    var dayCount: Int? {
        guard dateType == .multi else { return nil }
        let calendar = Calendar.current
        let startDay = calendar.startOfDay(for: sessionDate)
        let endDay = calendar.startOfDay(for: endDate)
        let days = calendar.dateComponents([.day], from: startDay, to: endDay).day ?? 0
        return days + 1
    }

    // MARK: - 折扣相關計算屬性

    /// 當前幣別
    var currentCurrency: Currency {
        return Currency(rawValue: selectedCurrency) ?? .twd
    }

    // MARK: - 日期範圍計算（用於 DatePicker 限制）

    /// 結束日期的可選範圍（多日場次：開始日期隔天 ~ +30天，確保至少 2 天）
    var endDateRange: ClosedRange<Date> {
        let calendar = Calendar.current
        let startDateDay = calendar.startOfDay(for: sessionDate)

        // 結束日期：從開始日期隔天開始，最多往後 30 天（總共 31 天）
        let minEndDate = calendar.date(byAdding: .day, value: 1, to: startDateDay)!
        let maxEndDate = calendar.date(byAdding: .day, value: 30, to: startDateDay)!

        return minEndDate...maxEndDate
    }

    init(sessionToEdit: SessionModel? = nil) {
        self.editingSession = sessionToEdit
        self.sessionName = sessionToEdit?.title ?? ""
        self.sessionDate = sessionToEdit?.startDate ?? Date()
        self.selectedCurrency = sessionToEdit?.currency ?? "TWD"
        self.categories = sessionToEdit?.categories ?? []
        self.discounts = sessionToEdit?.discounts ?? []

        // 初始化場次類型和結束日期
        self.dateType = sessionToEdit?.dateType ?? .single

        // 設定結束日期：若是編輯模式使用現有值，否則預設為開始日期 +1 天
        if let existingEndDate = sessionToEdit?.endDate {
            self.endDate = existingEndDate
        } else {
            let startDate = sessionToEdit?.startDate ?? Date()
            self.endDate = Calendar.current.date(byAdding: .day, value: 1, to: startDate) ?? startDate
        }
    }
    
    /// 更新 DataManager 引用
    func updateDataManagers(transactionDataManager: TransactionDataManager, productRepository: ProductRepository) {
        self.transactionDataManager = transactionDataManager
        self.productRepository = productRepository
    }

    func updateCategoryName(id: UUID, newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // 避免同名
        if categories.contains(where: { $0.name == trimmed && $0.id != id }) {
            return
        }

        if let index = categories.firstIndex(where: { $0.id == id }) {
            categories[index].name = trimmed
        }
    }

    func removeCategory(byId categoryId: UUID) {
        categories.removeAll { $0.id == categoryId }
    }
    
    func disableCategory(byId categoryId: UUID) {
        if let index = categories.firstIndex(where: { $0.id == categoryId }) {
            categories[index].isDisabled = true
        }
    }
    
    func restoreCategory(byId categoryId: UUID) {
        if let index = categories.firstIndex(where: { $0.id == categoryId }) {
            categories[index].isDisabled = false
        }
    }

    // MARK: - 折扣相關方法

    /// 嘗試新增折扣
    func tryAddDiscount() -> String? {
        let trimmed = newDiscountValue.trimmingCharacters(in: .whitespaces)

        guard !trimmed.isEmpty else {
            return "請輸入數值"
        }

        guard let value = Decimal(string: trimmed), value > 0 else {
            return "請輸入有效的數值"
        }

        // 驗證必須是整數（使用 NSDecimalNumber）
        let nsValue = NSDecimalNumber(decimal: value)
        let rounded = nsValue.rounding(accordingToBehavior: NSDecimalNumberHandler(
            roundingMode: .plain,
            scale: 0,
            raiseOnExactness: false,
            raiseOnOverflow: false,
            raiseOnUnderflow: false,
            raiseOnDivideByZero: false
        ))
        if nsValue.compare(rounded) != .orderedSame {
            return "折扣必須是整數"
        }

        // 百分比不可超過 100
        if newDiscountType == .percentage && value > 100 {
            return "百分比不可超過 100"
        }

        // 檢查是否重複
        let isDuplicate = discounts.contains {
            $0.type == newDiscountType && $0.value == value
        }
        if isDuplicate {
            return "此折扣已存在"
        }

        let discount = DiscountModel(type: newDiscountType, value: value)
        discounts.append(discount)
        newDiscountValue = ""
        return nil
    }

    /// 刪除折扣
    func deleteDiscount(_ discount: DiscountModel) {
        discounts.removeAll { $0.id == discount.id }
    }

    // MARK: - 類別相關方法

    // 嘗試將 newCategory 加入,成功則清空 newCategory,失敗回傳錯誤訊息
    func tryAddCategory() -> String? {
        let trimmed = newCategory.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else { return nil }

        if categories.contains(where: { $0.name == trimmed }) {
            return "此類別已存在"
        }

        let new = CategoryModel(id: UUID(), name: trimmed)
        categories.append(new)

        DispatchQueue.main.async {
            self.newCategory = ""
        }

        return nil
    }
    
    func hasTransaction(for categoryId: UUID? = nil) -> Bool {
        guard let sessionId = editingSession?.id else { return false }
        
        let transactions: [TransactionModel]
        if let transactionManager = transactionDataManager {
            transactions = transactionManager.fetchTransactions(forSessionId: sessionId)
        } else {
            transactions = []
        }
        
        // 如果沒有指定 categoryId，檢查是否有任何交易
        guard let categoryId = categoryId else {
            return !transactions.isEmpty
        }
        
        // 檢查特定類別的交易
        return transactions.contains { transaction in
            transaction.items.contains { $0.categoryId == categoryId }
        }
    }
    
    /// 檢查類別是否有產品（從最新數據源）
    func hasProducts(for categoryId: UUID) -> Bool {
        guard let sessionId = editingSession?.id,
              let productRepo = productRepository else {
            return false
        }
        let products = productRepo.fetchProducts(forSessionId: sessionId)
        return products.contains { $0.categoryId == categoryId }
    }

    /// 判斷類別是否可以編輯名稱（有交易記錄則不可編輯）
    func canEditCategoryName(for categoryId: UUID) -> Bool {
        return !hasTransaction(for: categoryId)
    }

    
    // MARK: - Alert 處理邏輯
    
    /// 處理停用操作
    func handleDisableAction(for categoryId: UUID) {
        alertMessage = "已有交易記錄不可刪除，只能停用"
        categoryPendingDeletion = categoryId
        isDisableAction = true
        showAlert = true
    }
    
    /// 處理刪除操作
    func handleDeleteAction(for category: CategoryModel) {
        if hasProducts(for: category.id) {
            // 有商品 → 警告後再刪除
            alertMessage = "此類別仍有產品，確定要刪除嗎？"
            categoryPendingDeletion = category.id
            isDisableAction = false
            showAlert = true
        } else {
            // 沒有商品 → 直接刪除
            removeCategory(byId: category.id)
        }
    }
    
    /// 處理復原操作
    func handleRestoreAction(for categoryId: UUID) {
        categoryPendingRestore = categoryId
        showAlert = true
    }
    
    /// 確認刪除/停用操作
    func confirmDeletionAction() {
        guard let categoryId = categoryPendingDeletion else { return }
        
        if isDisableAction {
            disableCategory(byId: categoryId)
        } else {
            removeCategory(byId: categoryId)
        }
        
        resetDeletionState()
    }
    
    /// 確認復原操作
    func confirmRestoreAction() {
        guard let categoryId = categoryPendingRestore else { return }
        restoreCategory(byId: categoryId)
        categoryPendingRestore = nil
    }
    
    /// 取消刪除/停用操作
    func cancelDeletionAction() {
        resetDeletionState()
    }
    
    /// 取消復原操作
    func cancelRestoreAction() {
        categoryPendingRestore = nil
    }
    
    /// 重置刪除狀態
    private func resetDeletionState() {
        categoryPendingDeletion = nil
        isDisableAction = false
    }
    
    /// 處理 Swipe Actions
    func getSwipeAction(for category: CategoryModel) -> SwipeActionType {
        if hasTransaction(for: category.id) {
            return .disable
        } else {
            return .delete
        }
    }
    
    /// 驗證保存條件
    func validateSave() -> ValidationResult {
        // 儲存前嘗試新增 newCategory
        if let error = tryAddCategory() {
            return .failure(error)
        }

        // 儲存前嘗試新增未按+的折扣（如果有輸入值）
        if !newDiscountValue.trimmingCharacters(in: .whitespaces).isEmpty {
            if let error = tryAddDiscount() {
                return .failure(error)
            }
        }

        if categories.filter({ !$0.isDisabled }).isEmpty {
            return .failure("請至少輸入一個類別")
        }

        // 驗證日期邏輯
        let dateValidation = validateDates()
        if !dateValidation.isValid {
            return .failure(dateValidation.errorMessage ?? "日期設定有誤")
        }

        return .success
    }

    /// 驗證日期設定
    func validateDates() -> (isValid: Bool, errorMessage: String?) {
        let calendar = Calendar.current

        switch dateType {
        case .single:
            // 單日場次：檢查是否包含所有交易日期
            if let sessionId = editingSession?.id {
                let transactionDateRange = getTransactionDateRange(for: sessionId)
                if let (minDate, maxDate) = transactionDateRange {
                    let sessionDay = calendar.startOfDay(for: sessionDate)
                    let minDay = calendar.startOfDay(for: minDate)
                    let maxDay = calendar.startOfDay(for: maxDate)

                    // 單日場次：所有交易必須在同一天
                    if minDay != sessionDay || maxDay != sessionDay {
                        let minDateStr = DateFormatter.sessionDate.string(from: minDate)
                        let maxDateStr = DateFormatter.sessionDate.string(from: maxDate)
                        return (false, "場次日期必須包含所有交易日期（\(minDateStr) - \(maxDateStr)）")
                    }
                }
            }
            return (true, nil)

        case .multi:
            // 多日場次：結束日期必須晚於開始日期
            let startDay = calendar.startOfDay(for: sessionDate)
            let endDay = calendar.startOfDay(for: endDate)

            guard endDay > startDay else {
                return (false, "結束日期必須晚於開始日期")
            }

            // 檢查至少需要 2 天
            let daysDifference = calendar.dateComponents([.day], from: startDay, to: endDay).day ?? 0
            guard daysDifference >= 1 else {
                return (false, "多日場次至少需要 2 天")
            }

            // 檢查最多 31 天
            let totalDays = daysDifference + 1  // 包含起始和結束日
            guard totalDays <= 31 else {
                return (false, "多日場次最多 31 天")
            }

            // 檢查是否包含所有交易日期
            if let sessionId = editingSession?.id {
                let transactionDateRange = getTransactionDateRange(for: sessionId)
                if let (minDate, maxDate) = transactionDateRange {
                    let minDay = calendar.startOfDay(for: minDate)
                    let maxDay = calendar.startOfDay(for: maxDate)

                    if startDay > minDay || endDay < maxDay {
                        let minDateStr = DateFormatter.sessionDate.string(from: minDate)
                        let maxDateStr = DateFormatter.sessionDate.string(from: maxDate)
                        return (false, "場次日期必須包含所有交易日期（\(minDateStr) - \(maxDateStr)）")
                    }
                }
            }

            return (true, nil)

        case .permanent:
            // 無限期場次：檢查開始日期是否早於最早的交易
            if let sessionId = editingSession?.id {
                let transactionDateRange = getTransactionDateRange(for: sessionId)
                if let (minDate, _) = transactionDateRange {
                    let startDay = calendar.startOfDay(for: sessionDate)
                    let minDay = calendar.startOfDay(for: minDate)

                    if startDay > minDay {
                        let minDateStr = DateFormatter.sessionDate.string(from: minDate)
                        return (false, "場次開始日期必須早於或等於最早的交易日期（\(minDateStr)）")
                    }
                }
            }
            return (true, nil)
        }
    }

    /// 取得場次的交易日期範圍（最早和最晚的交易日期）
    private func getTransactionDateRange(for sessionId: UUID) -> (min: Date, max: Date)? {
        guard let transactionManager = transactionDataManager else { return nil }

        let transactions = transactionManager.fetchTransactions(forSessionId: sessionId)

        guard !transactions.isEmpty else { return nil }

        let dates = transactions.map { $0.timestamp }
        guard let minDate = dates.min(), let maxDate = dates.max() else { return nil }

        return (minDate, maxDate)
    }

    func save() -> SessionModel {
        let baseSession = editingSession ?? SessionModel(
            title: "",
            startDate: Date(),
            endDate: Date(),
            dateType: .single,
            categories: [],
            createdAt: Date()
        )

        // 根據場次類型設定 endDate
        let finalEndDate: Date?
        switch dateType {
        case .single:
            finalEndDate = sessionDate  // 單日場次：endDate = startDate
        case .multi:
            finalEndDate = endDate      // 多日場次：使用選擇的 endDate
        case .permanent:
            finalEndDate = nil          // 無限期場次：endDate = nil
        }

        return SessionModel(
            id: baseSession.id,
            title: sessionName,
            startDate: sessionDate,
            endDate: finalEndDate,
            dateType: dateType,
            categories: categories,
            createdAt: baseSession.createdAt,
            currency: selectedCurrency,
            discounts: discounts
        )
    }
}

// MARK: - Helper Enums

enum SwipeActionType {
    case delete
    case disable
}

enum ValidationResult {
    case success
    case failure(String)
}
