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

    var roundingMode: RoundingMode {
        return .plain  // 所有貨幣都使用一般四捨五入
    }
}

class MoneyHelper {
    static var currentCurrency: Currency = .twd

    // 無限精度處理器（用於中間計算，不四捨五入）
    private static let noRoundingHandler = NSDecimalNumberHandler(
        roundingMode: .plain,
        scale: Int16.max,  // 保留最大精度
        raiseOnExactness: false,
        raiseOnOverflow: false,
        raiseOnUnderflow: false,
        raiseOnDivideByZero: false
    )

    // 四捨五入處理器（只用於最終結果）
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

    // MARK: - 基本運算（保留完整精度，不四捨五入）

    static func add(_ a: Decimal, _ b: Decimal, roundingMode: RoundingMode? = nil) -> Decimal {
        let nsA = NSDecimalNumber(decimal: a)
        let nsB = NSDecimalNumber(decimal: b)
        if let mode = roundingMode {
            let handler = getHandler(for: mode)
            return nsA.adding(nsB, withBehavior: handler).decimalValue
        }
        // 預設不四捨五入，保留完整精度
        return nsA.adding(nsB, withBehavior: noRoundingHandler).decimalValue
    }

    static func subtract(_ a: Decimal, _ b: Decimal, roundingMode: RoundingMode? = nil) -> Decimal {
        let nsA = NSDecimalNumber(decimal: a)
        let nsB = NSDecimalNumber(decimal: b)
        if let mode = roundingMode {
            let handler = getHandler(for: mode)
            return nsA.subtracting(nsB, withBehavior: handler).decimalValue
        }
        return nsA.subtracting(nsB, withBehavior: noRoundingHandler).decimalValue
    }

    static func multiply(_ a: Decimal, _ b: Decimal, roundingMode: RoundingMode? = nil) -> Decimal {
        let nsA = NSDecimalNumber(decimal: a)
        let nsB = NSDecimalNumber(decimal: b)
        if let mode = roundingMode {
            let handler = getHandler(for: mode)
            return nsA.multiplying(by: nsB, withBehavior: handler).decimalValue
        }
        return nsA.multiplying(by: nsB, withBehavior: noRoundingHandler).decimalValue
    }

    static func divide(_ a: Decimal, _ b: Decimal, roundingMode: RoundingMode? = nil) -> Decimal {
        let nsA = NSDecimalNumber(decimal: a)
        let nsB = NSDecimalNumber(decimal: b)
        if let mode = roundingMode {
            let handler = getHandler(for: mode)
            return nsA.dividing(by: nsB, withBehavior: handler).decimalValue
        }
        return nsA.dividing(by: nsB, withBehavior: noRoundingHandler).decimalValue
    }

    // MARK: - 進階運算（中間計算不四捨五入，只在最終結果四捨五入）

    static func applyDiscount(price: Decimal, discountPercentage: Int, roundingMode: RoundingMode? = nil) -> Decimal {
        let discount = Decimal(discountPercentage) / Decimal(100)
        let discountAmount = multiply(price, discount)  // 中間不四捨五入
        let result = subtract(price, discountAmount)    // 中間不四捨五入
        // 只在有指定 roundingMode 時才四捨五入
        if let mode = roundingMode {
            return round(result, roundingMode: mode)
        }
        return result
    }

    static func calculateTotal(price: Decimal, quantity: Int, discountPercentage: Int = 0, roundingMode: RoundingMode? = nil) -> Decimal {
        let discountedPrice = applyDiscount(price: price, discountPercentage: discountPercentage)  // 不四捨五入
        let result = multiply(discountedPrice, Decimal(quantity))  // 不四捨五入
        // 只在有指定 roundingMode 時才四捨五入
        if let mode = roundingMode {
            return round(result, roundingMode: mode)
        }
        return result
    }

    static func round(_ value: Decimal, roundingMode: RoundingMode = .bankers) -> Decimal {
        let nsValue = NSDecimalNumber(decimal: value)
        let handler = getHandler(for: roundingMode)
        return nsValue.rounding(accordingToBehavior: handler).decimalValue
    }

    static func format(_ value: Decimal, currency: String = "NT$") -> String {
        // 使用當前貨幣設定的規則
        return format(value, currency: currentCurrency)
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

    // MARK: - Advanced Helper Methods

    /// 計算平均值（預設不四捨五入，保留完整精度）
    static func average(total: Decimal, count: Int, roundingMode: RoundingMode? = nil) -> Decimal {
        guard count > 0 else { return 0 }
        let result = divide(total, Decimal(count))  // 中間不四捨五入
        if let mode = roundingMode {
            return round(result, roundingMode: mode)
        }
        return result
    }

    /// 計算總和（預設不四捨五入，保留完整精度）
    static func sum(_ values: [Decimal], roundingMode: RoundingMode? = nil) -> Decimal {
        let result = values.reduce(Decimal(0)) { result, value in
            add(result, value)  // 中間不四捨五入
        }
        if let mode = roundingMode {
            return round(result, roundingMode: mode)
        }
        return result
    }

    static func format(_ value: Decimal, currency: Currency) -> String {
        // 先根據貨幣規則四捨五入
        let handler = getHandlerForCurrency(currency)
        let roundedValue = NSDecimalNumber(decimal: value).rounding(accordingToBehavior: handler).decimalValue

        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = currency.decimalPlaces
        formatter.maximumFractionDigits = currency.decimalPlaces

        if let formattedNumber = formatter.string(from: NSDecimalNumber(decimal: roundedValue)) {
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

    private static func getHandlerForCurrency(_ currency: Currency) -> NSDecimalNumberHandler {
        let nsRoundingMode: NSDecimalNumber.RoundingMode
        switch currency.roundingMode {
        case .bankers:
            nsRoundingMode = .bankers
        case .plain:
            nsRoundingMode = .plain
        case .down:
            nsRoundingMode = .down
        case .up:
            nsRoundingMode = .up
        }

        return NSDecimalNumberHandler(
            roundingMode: nsRoundingMode,
            scale: Int16(currency.decimalPlaces),
            raiseOnExactness: false,
            raiseOnOverflow: false,
            raiseOnUnderflow: false,
            raiseOnDivideByZero: false
        )
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