//
//  MoneyHelper.swift
//  Tilli
//
//  Created by Claude on 2025/09/26.
//

import Foundation

enum RoundingMode {
    case bankers
    case plain
    case down
    case up
}

enum Currency: String, CaseIterable {
    case twd = "TWD"
    case usd = "USD"
    case eur = "EUR"
    case jpy = "JPY"

    var symbol: String {
        switch self {
        case .twd: return "NT$"
        case .usd: return "$"
        case .eur: return "€"
        case .jpy: return "¥"
        }
    }

    var decimalPlaces: Int {
        switch self {
        case .twd: return 0
        case .usd: return 2
        case .eur: return 2
        case .jpy: return 0
        }
    }

    var displayName: String {
        switch self {
        case .twd: return "新台幣"
        case .usd: return "美金"
        case .eur: return "歐元"
        case .jpy: return "日幣"
        }
    }
}

class MoneyHelper {
    static var currentCurrency: Currency = .twd

    private static let handler = NSDecimalNumberHandler(
        roundingMode: .bankers,
        scale: 2,
        raiseOnExactness: false,
        raiseOnOverflow: false,
        raiseOnUnderflow: false,
        raiseOnDivideByZero: false
    )

    private static let plainRoundingHandler = NSDecimalNumberHandler(
        roundingMode: .plain,
        scale: 2,
        raiseOnExactness: false,
        raiseOnOverflow: false,
        raiseOnUnderflow: false,
        raiseOnDivideByZero: false
    )

    private static let downRoundingHandler = NSDecimalNumberHandler(
        roundingMode: .down,
        scale: 2,
        raiseOnExactness: false,
        raiseOnOverflow: false,
        raiseOnUnderflow: false,
        raiseOnDivideByZero: false
    )

    private static let upRoundingHandler = NSDecimalNumberHandler(
        roundingMode: .up,
        scale: 2,
        raiseOnExactness: false,
        raiseOnOverflow: false,
        raiseOnUnderflow: false,
        raiseOnDivideByZero: false
    )

    static func add(_ a: Decimal, _ b: Decimal, roundingMode: RoundingMode = .bankers) -> Decimal {
        let nsA = NSDecimalNumber(decimal: a)
        let nsB = NSDecimalNumber(decimal: b)
        let handler = getHandler(for: roundingMode)
        return nsA.adding(nsB, withBehavior: handler).decimalValue
    }

    static func subtract(_ a: Decimal, _ b: Decimal, roundingMode: RoundingMode = .bankers) -> Decimal {
        let nsA = NSDecimalNumber(decimal: a)
        let nsB = NSDecimalNumber(decimal: b)
        let handler = getHandler(for: roundingMode)
        return nsA.subtracting(nsB, withBehavior: handler).decimalValue
    }

    static func multiply(_ a: Decimal, _ b: Decimal, roundingMode: RoundingMode = .bankers) -> Decimal {
        let nsA = NSDecimalNumber(decimal: a)
        let nsB = NSDecimalNumber(decimal: b)
        let handler = getHandler(for: roundingMode)
        return nsA.multiplying(by: nsB, withBehavior: handler).decimalValue
    }

    static func divide(_ a: Decimal, _ b: Decimal, roundingMode: RoundingMode = .bankers) -> Decimal {
        let nsA = NSDecimalNumber(decimal: a)
        let nsB = NSDecimalNumber(decimal: b)
        let handler = getHandler(for: roundingMode)
        return nsA.dividing(by: nsB, withBehavior: handler).decimalValue
    }

    static func applyDiscount(price: Decimal, discountPercentage: Int, roundingMode: RoundingMode = .bankers) -> Decimal {
        let discount = Decimal(discountPercentage) / Decimal(100)
        let discountAmount = multiply(price, discount, roundingMode: roundingMode)
        return subtract(price, discountAmount, roundingMode: roundingMode)
    }

    static func calculateTotal(price: Decimal, quantity: Int, discountPercentage: Int = 0, roundingMode: RoundingMode = .bankers) -> Decimal {
        let discountedPrice = applyDiscount(price: price, discountPercentage: discountPercentage, roundingMode: roundingMode)
        return multiply(discountedPrice, Decimal(quantity), roundingMode: roundingMode)
    }

    static func round(_ value: Decimal, roundingMode: RoundingMode = .bankers) -> Decimal {
        let nsValue = NSDecimalNumber(decimal: value)
        let handler = getHandler(for: roundingMode)
        return nsValue.rounding(accordingToBehavior: handler).decimalValue
    }

    static func format(_ value: Decimal, currency: String = "NT$") -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2

        if let formattedNumber = formatter.string(from: NSDecimalNumber(decimal: value)) {
            return "\(currency)\(formattedNumber)"
        }
        return "\(currency)0"
    }

    static func fromDouble(_ value: Double) -> Decimal {
        return Decimal(value)
    }

    static func toDouble(_ value: Decimal) -> Double {
        return NSDecimalNumber(decimal: value).doubleValue
    }

    static func switchToCurrency(_ currency: Currency) {
        currentCurrency = currency
    }

    static func format(_ value: Decimal, currency: Currency) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = currency.decimalPlaces
        formatter.maximumFractionDigits = currency.decimalPlaces

        if let formattedNumber = formatter.string(from: NSDecimalNumber(decimal: value)) {
            return "\(currency.symbol)\(formattedNumber)"
        }
        return "\(currency.symbol)0"
    }

    private static func getHandler(for mode: RoundingMode) -> NSDecimalNumberHandler {
        switch mode {
        case .bankers:
            return handler
        case .plain:
            return plainRoundingHandler
        case .down:
            return downRoundingHandler
        case .up:
            return upRoundingHandler
        }
    }
}

extension Decimal {
    var money: String {
        return MoneyHelper.format(self)
    }

    func money(currency: String) -> String {
        return MoneyHelper.format(self, currency: currency)
    }
}