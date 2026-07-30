import XCTest
@testable import Tilli

final class TilliSmokeTests: XCTestCase {
    func testEventMock() {
        let event = EventModel.mock()
        XCTAssertFalse(event.title.isEmpty)
        XCTAssertEqual(event.currency, "TWD")
        XCTAssertEqual(event.dateType, .single)
    }

    func testProductMock() {
        let product = ProductModel.mock()
        XCTAssertFalse(product.name.isEmpty)
        XCTAssertEqual(product.price, 100)
        XCTAssertEqual(product.stock, 10)
        XCTAssertFalse(product.isDisabled)
    }
}
