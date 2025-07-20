//
//  SessionDetailViewModel.swift
//  Tilli
//
//  Created by Peiyun on 2025/7/8.
//

import Foundation

class SessionDetailViewModel: ObservableObject {
    let session: SessionModel

    @Published var quantities: [UUID: Int] = [:]
    @Published var selectedDiscounts: [UUID: Int] = [:]
    @Published var selectedTab: Int = 0

    init(session: SessionModel) {
        self.session = session
    }

    func increaseQuantity(for product: ProductModel) {
        let current = quantities[product.id, default: 0]
        if current < product.quantity {
            quantities[product.id] = current + 1
        }
    }

    func decreaseQuantity(for product: ProductModel) {
        let current = quantities[product.id, default: 0]
        if current > 0 {
            quantities[product.id] = current - 1
        }
    }

    func toggleDiscount(for product: ProductModel, percent: Int) {
        if selectedDiscounts[product.id] == percent {
            selectedDiscounts[product.id] = nil
        } else {
            selectedDiscounts[product.id] = percent
        }
    }

    func isDiscountSelected(for product: ProductModel, percent: Int) -> Bool {
        selectedDiscounts[product.id] == percent
    }

    func quantity(for product: ProductModel) -> Int {
        quantities[product.id, default: 0]
    }
    
    func clearAllQuantities() {
        quantities.removeAll()
    }

    func totalAmount() -> Int {
        session.products.reduce(0) { result, product in
            let qty = quantities[product.id, default: 0]
            let discount = selectedDiscounts[product.id] ?? 0
            let discountedPrice = product.price * (1 - Double(discount) / 100)
            let roundedTotal = (discountedPrice * Double(qty)).rounded()
            return result + Int(roundedTotal)
        }
    }

    
    func selectedProductsWithQuantityAndDiscount() -> [SummaryItemModel] {
        session.products.compactMap { product in
            let qty = quantities[product.id, default: 0]
            guard qty > 0 else { return nil }
            let discount = selectedDiscounts[product.id, default: 0]
            return SummaryItemModel(product: product, quantity: qty, discount: discount)
        }
    }


}
