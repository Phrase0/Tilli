//
//  BundleFormViewModel.swift
//  Tilli
//
//  新增／編輯套餐（fixed）或組合（chooseAny）的表單。
//  見 docs/superpowers/specs/2026-10-27-bundles-design.md §4.2、§4.3。
//

import SwiftUI

@MainActor
final class BundleFormViewModel: ObservableObject {

    @Published var name: String
    @Published var priceText: String
    /// chooseAny 的 N
    @Published var count: Int
    /// 勾選順序即成員／候選順序
    @Published var selectedProductIds: [UUID]
    /// 只有套餐顯示
    @Published var image: UIImage? {
        didSet { imageChanged = true }
    }

    @Published var showImagePicker = false
    @Published var showSaveFailedAlert = false

    let kind: BundleKind
    let editing: BundleModel?

    static let countRange = 2...99

    private let event: EventModel
    private let products: [ProductModel]
    private let productsById: [UUID: ProductModel]
    /// 新增時預先決定 id 與建立時間，讓照片與資料寫到同一個 id
    private let bundleId: UUID
    private let createdAt: Date
    private var imageChanged = false

    init(kind: BundleKind, editing: BundleModel?, event: EventModel, products: [ProductModel]) {
        self.kind = kind
        self.editing = editing
        self.event = event
        self.products = products
        self.productsById = Dictionary(products.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.bundleId = editing?.id ?? UUID()
        self.createdAt = editing?.createdAt ?? Date()

        let currency = Currency(rawValue: event.currency) ?? .twd
        self.name = editing?.name ?? ""
        self.priceText = editing.map { MoneyHelper.toEditableString($0.price, currency: currency) } ?? ""
        if case .chooseAny(let n) = editing?.mode {
            self.count = n
        } else {
            self.count = 3
        }
        self.selectedProductIds = editing?.productIds ?? []
        self.image = (kind == .fixed && editing != nil) ? BundleImageStore.load(for: bundleId) : nil
        // 初始值不算「使用者改過照片」
        self.imageChanged = false
    }

    // MARK: - 顯示

    var currency: Currency { Currency(rawValue: event.currency) ?? .twd }

    var supportsDecimal: Bool { currency.decimalPlaces > 0 }

    var pricePlaceholder: String { "\(currency.symbol) 0" }

    /// 勾選清單：依類別順序、類別內依商品順序（含已下架者）
    var selectableProducts: [ProductModel] {
        let categoryOrder = Dictionary(event.categories.map { ($0.id, $0.sortOrder) }, uniquingKeysWith: { first, _ in first })
        return products.sorted { lhs, rhs in
            let l = categoryOrder[lhs.categoryId] ?? Int.max
            let r = categoryOrder[rhs.categoryId] ?? Int.max
            if l != r { return l < r }
            if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    /// 已下架或類別停用：可勾選，但灰色並標示（設計 §4.2）
    func isUnavailable(_ product: ProductModel) -> Bool {
        product.saleAvailability(in: event.categories) != .available
    }

    func isSelected(_ productId: UUID) -> Bool {
        selectedProductIds.contains(productId)
    }

    func toggle(_ productId: UUID) {
        if let index = selectedProductIds.firstIndex(of: productId) {
            selectedProductIds.remove(at: index)
        } else {
            selectedProductIds.append(productId)
        }
    }

    /// 只留數字與一個小數點，小數位數依幣別（與商品表單同一份規則：MoneyHelper.sanitizeInput）
    func sanitizePrice() {
        let sanitized = MoneyHelper.sanitizeInput(
            priceText, currency: currency, maxIntegerDigits: AddNewProductViewModel.priceMaxIntegerDigits
        )
        if sanitized != priceText { priceText = sanitized }
    }

    // MARK: - 計算

    private var price: Decimal {
        Decimal(string: priceText.trimmingCharacters(in: .whitespaces)) ?? 0
    }

    private var draft: BundleModel {
        BundleModel(
            id: bundleId,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            price: price,
            mode: kind == .fixed ? .fixed : .chooseAny(count: count),
            productIds: selectedProductIds,
            isDisabled: editing?.isDisabled ?? false,
            imageURL: editing?.imageURL,
            createdAt: createdAt
        )
    }

    /// 表單「原價合計」提示：已勾選成員的單價合計
    var originalTotal: Decimal {
        MoneyHelper.sum(selectedProductIds.compactMap { productsById[$0]?.price })
    }

    var errors: [BundleValidationError] {
        BundleValidator.validate(draft, existing: event.bundles, products: productsById)
    }

    /// 有任何錯誤（含還沒填完）儲存鈕就變灰
    var canSave: Bool { errors.isEmpty }

    // 錯誤即時顯示在各欄位下方，但只顯示「填了但填錯」的；還沒填（名稱空白、價格空白）只讓儲存變灰，
    // 避免剛打開表單就一片紅字。

    /// 名稱欄下方紅字：與現有套餐／組合重名
    var nameError: String? {
        errors.contains(.duplicateName) ? errorText(.duplicateName) : nil
    }

    /// 價格欄下方紅字：超過上限，或填了但不大於 0
    var priceError: String? {
        if let aboveLimit = errors.first(where: { if case .priceAboveLimit = $0 { return true } else { return false } }) {
            return errorText(aboveLimit)
        }
        if !priceText.isEmpty && errors.contains(.nonPositivePrice) {
            return errorText(.nonPositivePrice)
        }
        return nil
    }

    /// 勾選區下方灰字：還沒勾夠（不算填錯，所以不用紅字）
    var selectionHint: String? {
        if errors.contains(.tooFewMembers) { return errorText(.tooFewMembers) }
        if errors.contains(.noCandidates) { return errorText(.noCandidates) }
        return nil
    }

    /// 勾選區下方紅字：有成員商品已不存在
    var selectionError: String? {
        errors.contains(.unknownProduct) ? errorText(.unknownProduct) : nil
    }

    /// 組合：「上限 $X（N × 最便宜的 $Y）」，常駐顯示在價格下方；套餐的上限就是原價合計（見 originalTotalHint）
    var comboLimitHint: String? {
        guard case .chooseAny(let n) = draft.mode,
              let limit = BundleValidator.priceLimit(for: draft, products: productsById),
              let cheapest = selectedProductIds.compactMap({ productsById[$0]?.price }).min() else { return nil }
        // 上限 %1$@（%2$lld × 最便宜的 %3$@）
        return String.localized("bundleComboLimitHint \(MoneyHelper.format(limit, currency: currency)) \(n) \(MoneyHelper.format(cheapest, currency: currency))")
    }

    var showsNoDiscountHint: Bool {
        price > 0 && BundleValidator.hasNoDiscount(draft, products: productsById)
    }

    /// 套餐：「原價合計 $X，套餐價省 $Y」；沒有省錢時只顯示原價合計
    var originalTotalHint: String? {
        guard kind == .fixed, !selectedProductIds.isEmpty else { return nil }
        let total = MoneyHelper.format(originalTotal, currency: currency)
        let saving = MoneyHelper.subtract(originalTotal, price)
        if price > 0, saving > 0 {
            // 原價合計 %@，套餐價省 %@
            return String.localized("bundleOriginalTotalHint \(total) \(MoneyHelper.format(saving, currency: currency))")
        }
        // 原價合計 %@
        return String.localized("bundleOriginalTotalOnly \(total)")
    }

    // MARK: - 儲存

    /// 驗證通過才回傳要寫入的完整陣列（新增則 append，編輯則替換同 id）
    func bundlesToSave() -> [BundleModel]? {
        guard errors.isEmpty else { return nil }
        var bundles = event.bundles
        if editing != nil {
            // 編輯中的套餐已被刪除：拒絕，不改成新增
            guard let index = bundles.firstIndex(where: { $0.id == bundleId }) else { return nil }
            bundles[index] = draft
        } else {
            bundles.append(draft)
        }
        return bundles
    }

    /// 寫入場次並處理套餐照片。失敗時不關閉表單並顯示提示。
    func save(using eventRepository: EventRepository) -> Bool {
        guard let bundles = bundlesToSave() else { return false }

        // 照片先寫：失敗就整個不存。寫之前備份原本的照片（新增時為 nil），
        // 資料存失敗時還原，編輯時換掉或移除的照片才不會遺失
        let changesImage = kind == .fixed && imageChanged
        let previousImageData = changesImage ? BundleImageStore.data(for: bundleId) : nil
        if changesImage {
            if let image {
                guard BundleImageStore.save(image, for: bundleId) else {
                    BundleImageStore.restore(previousImageData, for: bundleId)
                    showSaveFailedAlert = true
                    return false
                }
            } else {
                BundleImageStore.delete(for: bundleId)
            }
        }

        guard eventRepository.saveBundles(bundles, forEventId: event.id) else {
            if changesImage { BundleImageStore.restore(previousImageData, for: bundleId) }
            showSaveFailedAlert = true
            return false
        }
        return true
    }

    private func errorText(_ error: BundleValidationError) -> String {
        switch error {
        case .emptyName:
            // 請輸入名稱
            return String.localized("bundleErrorEmptyName")
        case .duplicateName:
            // 已有相同名稱的套餐或組合
            return String.localized("bundleErrorDuplicateName")
        case .nonPositivePrice:
            // 價格必須大於 0
            return String.localized("bundleErrorNonPositivePrice")
        case .tooFewMembers:
            // 套餐至少要選 2 個商品
            return String.localized("bundleErrorTooFewMembers")
        case .countTooSmall:
            // 任選數量至少要 2 個
            return String.localized("bundleErrorCountTooSmall")
        case .noCandidates:
            // 請至少選 1 個商品
            return String.localized("bundleErrorNoCandidates")
        case .unknownProduct:
            // 有商品已不存在，請重新勾選
            return String.localized("bundleErrorUnknownProduct")
        case .priceAboveLimit(let limit):
            // 價格不能超過 %@
            return String.localized("bundleErrorPriceAboveLimit \(MoneyHelper.format(limit, currency: currency))")
        }
    }
}
