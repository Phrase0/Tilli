//
//  CartPricing.swift
//  Tilli
//
//  購物車的定價明細（訂單摘要、底部總計列）與結帳寫入用的拆列：純計算，無狀態。
//
//  ⭐ 順序：套餐／組合差額 → 百分比 → 減額。
//    - 小計 = Σ 單點原價 + Σ 套餐價（套餐差額已不在小計裡）
//    - 整筆折扣的基礎 = 小計 − Σ 組合差額
//  ⭐ 保證（CartPricingTests 鎖住）：`summaryItems` 交給 `RevenueAllocator.allocate` 後，
//    Σ actualRevenue == total，Σ bundleDiscount == Σ 套餐差額 + Σ 組合差額。
//

import Foundation

struct CartPricing: Equatable {

    struct BundleRow: Equatable {
        let bundle: BundleModel
        let quantity: Int
        let lineTotal: Decimal          // 套餐價 × 份數
    }

    struct ProductRow: Equatable {
        let product: ProductModel
        let quantity: Int
        let lineTotal: Decimal          // 原價 × 數量
        let isInCombo: Bool             // 有任何數量被組合涵蓋（「含組合」小標）
    }

    let bundleRows: [BundleRow]
    let productRows: [ProductRow]
    let combos: [ComboApplication]
    let subtotal: Decimal               // Σ 商品原價 + Σ 套餐價（訂單摘要的「小計」）
    let discounts: [AppliedDiscount]    // 以 subtotal − Σ combo.deduction 為基礎
    let total: Decimal

    /// 套餐成員展開時要查單價與類別；只給 `summaryItems` 用。
    private let products: [UUID: ProductModel]

    /// 整筆折扣（百分比、減額）的基礎 = 小計 − Σ 組合差額
    var discountBase: Decimal {
        Self.discountBase(subtotal: subtotal, deductions: combos.map(\.deduction))
    }

    /// 整筆折扣基礎的**唯一實作**：小計 − Σ 已先扣的套餐／組合差額。
    /// 定價（小計已是套餐價 → 只扣組合差額）、收銀頁的折扣上限提示、
    /// 結帳寫入（`CheckoutRecorder`：小計是成員原價 → 扣套餐＋組合差額）都走這裡。
    static func discountBase(subtotal: Decimal, deductions: [Decimal]) -> Decimal {
        MoneyHelper.subtract(subtotal, MoneyHelper.sum(deductions))
    }

    /// 共省 = 小計 − 總計（套餐差額已在小計外，不重複計入）
    var savings: Decimal {
        MoneyHelper.subtract(subtotal, total)
    }

    // MARK: - 定價

    /// 購物車 → 定價明細。
    /// 套餐行用 `bundles` 裡的現行套餐計價；套餐或任一成員找不到的行略過（失效行由收銀頁另行處理）；
    /// 單點商品找不到的也略過。組合只取 `bundles` 中 `.chooseAny` 的，交給 `ComboApplier`。
    static func price(
        cart: Cart,
        products: [UUID: ProductModel],
        bundles: [UUID: BundleModel],
        categories: [CategoryModel],
        selectedDiscounts: [DiscountModel]
    ) -> CartPricing {
        let bundleRows = cart.bundleLines
            .compactMap { id, line -> BundleRow? in
                // 套餐或任一成員不存在 → 整行略過，定價與 summaryItems 才不會對不起來
                guard line.quantity > 0,
                      let bundle = bundles[id],
                      bundle.productIds.allSatisfy({ products[$0] != nil }) else { return nil }
                return BundleRow(
                    bundle: bundle,
                    quantity: line.quantity,
                    lineTotal: MoneyHelper.multiply(bundle.price, Decimal(line.quantity))
                )
            }
            .sorted { lhs, rhs in
                if lhs.bundle.createdAt != rhs.bundle.createdAt { return lhs.bundle.createdAt < rhs.bundle.createdAt }
                return lhs.bundle.id.uuidString < rhs.bundle.id.uuidString
            }

        let combos = ComboApplier.apply(
            cart: cart,
            combos: bundles.values.filter { $0.kind == .chooseAny },
            products: products,
            categories: categories
        )
        let coveredIds = Set(combos.flatMap { $0.coveredQuantities.filter { $0.value > 0 }.keys })

        let productRows = cart.productQuantities
            .compactMap { id, quantity -> ProductRow? in
                guard quantity > 0, let product = products[id] else { return nil }
                return ProductRow(
                    product: product,
                    quantity: quantity,
                    lineTotal: MoneyHelper.multiply(product.price, Decimal(quantity)),
                    isInCombo: coveredIds.contains(id)
                )
            }
            .sorted { lhs, rhs in
                if lhs.product.createdAt != rhs.product.createdAt { return lhs.product.createdAt < rhs.product.createdAt }
                return lhs.product.id.uuidString < rhs.product.id.uuidString
            }

        let subtotal = MoneyHelper.add(
            MoneyHelper.sum(bundleRows.map(\.lineTotal)),
            MoneyHelper.sum(productRows.map(\.lineTotal))
        )
        let discountBase = Self.discountBase(subtotal: subtotal, deductions: combos.map(\.deduction))

        return CartPricing(
            bundleRows: bundleRows,
            productRows: productRows,
            combos: combos,
            subtotal: subtotal,
            discounts: DiscountCalculator.applied(for: selectedDiscounts, subtotal: discountBase),
            total: DiscountCalculator.total(subtotal: discountBase, discounts: selectedDiscounts),
            products: products
        )
    }

    // MARK: - 結帳寫入

    /// 結帳寫入用：套餐展開成成員列（bundleId/bundleName/bundleKind = .fixed，quantity = 份數）；
    /// 單點商品依 combos 拆成「被組合涵蓋」（bundleKind = .chooseAny）與「未涵蓋」兩種列。
    ///
    /// - 套餐成員重複（如大福 ×2）合併成一列，數量 = 出現次數 × 份數。
    /// - 一個商品被兩個組合涵蓋時，每個組合各一列（依 `combos` 的套用順序），再接未涵蓋的一列。
    /// - 套餐差額 = (Σ 成員單價 − 套餐價) × 份數；組合差額 = `ComboApplication.deduction`。
    ///
    /// `bundleRows` 只含成員齊全的套餐（`price` 已過濾），所以每個成員都查得到。
    func summaryItems(
        categoryName: (UUID) -> String,
        timestamp: Date
    ) -> (items: [SummaryItemModel], bundleDeductions: [RevenueAllocator.BundleDeduction]) {
        var items: [SummaryItemModel] = []
        var deductions: [RevenueAllocator.BundleDeduction] = []

        func makeItem(_ product: ProductModel, quantity: Int, bundleId: UUID?, bundleName: String?, kind: BundleKind?) -> SummaryItemModel {
            SummaryItemModel(
                productId: product.id,
                name: product.name,
                price: product.price,
                categoryId: product.categoryId,
                category: categoryName(product.categoryId),
                quantity: quantity,
                timestamp: timestamp,
                bundleId: bundleId,
                bundleName: bundleName,
                bundleKind: kind
            )
        }

        // 套餐 → 成員列
        for row in bundleRows {
            var occurrences: [UUID: Int] = [:]
            var orderedIds: [UUID] = []
            for id in row.bundle.productIds {
                if occurrences[id] == nil { orderedIds.append(id) }
                occurrences[id, default: 0] += 1
            }

            var memberTotal: Decimal = 0
            for id in orderedIds {
                guard let product = products[id] else { continue }
                let count = occurrences[id] ?? 0
                memberTotal = MoneyHelper.add(memberTotal, MoneyHelper.multiply(product.price, Decimal(count)))
                items.append(makeItem(
                    product,
                    quantity: count * row.quantity,
                    bundleId: row.bundle.id,
                    bundleName: row.bundle.name,
                    kind: .fixed
                ))
            }

            let perServing = MoneyHelper.subtract(memberTotal, row.bundle.price)
            deductions.append(.init(
                bundleId: row.bundle.id,
                amount: MoneyHelper.multiply(perServing, Decimal(row.quantity))
            ))
        }

        // 單點 → 依組合拆列
        for row in productRows {
            var remaining = row.quantity
            for combo in combos {
                let covered = min(combo.coveredQuantities[row.product.id] ?? 0, remaining)
                guard covered > 0 else { continue }
                items.append(makeItem(row.product, quantity: covered, bundleId: combo.bundleId, bundleName: combo.name, kind: .chooseAny))
                remaining -= covered
            }
            if remaining > 0 {
                items.append(makeItem(row.product, quantity: remaining, bundleId: nil, bundleName: nil, kind: nil))
            }
        }

        deductions += combos.map { .init(bundleId: $0.bundleId, amount: $0.deduction) }
        return (items, deductions)
    }
}
