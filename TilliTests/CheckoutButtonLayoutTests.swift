import XCTest
import SwiftUI
@testable import Tilli

/// 結帳鈕：窄螢幕＋大金額時先拿掉劃線原價，金額不可被截成「…」
@MainActor
final class CheckoutButtonLayoutTests: XCTestCase {

    private func width(of label: CheckoutButtonLabel, in available: CGFloat) -> CGFloat {
        UIHostingController(rootView: label).sizeThatFits(in: CGSize(width: available, height: 100)).width
    }

    func testLargeAmountsFitNarrowButton() {
        let label = CheckoutButtonLabel(subtotal: 123_456, total: 111_111, savings: 12_345, currency: "TWD")
        XCTAssertLessThanOrEqual(width(of: label, in: 220), 220)
    }

    func testFullLabelWhenThereIsRoom() {
        let label = CheckoutButtonLabel(subtotal: 250, total: 189, savings: 61, currency: "TWD")
        let noDiscount = CheckoutButtonLabel(subtotal: 189, total: 189, savings: 0, currency: "TWD")
        // 理想寬度：有折扣時保留劃線原價，所以比沒有折扣的版本寬
        func idealWidth(_ view: CheckoutButtonLabel) -> CGFloat {
            UIHostingController(rootView: view.fixedSize()).sizeThatFits(in: CGSize(width: 600, height: 100)).width
        }
        XCTAssertGreaterThan(idealWidth(label), idealWidth(noDiscount))
    }
}
