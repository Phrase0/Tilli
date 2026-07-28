import XCTest
@testable import Tilli

final class TilliSmokeTests: XCTestCase {
    func testSessionMock() {
        let session = SessionModel.mock()
        XCTAssertFalse(session.title.isEmpty)
        XCTAssertEqual(session.currency, "TWD")
        XCTAssertEqual(session.dateType, .single)
    }

    func testProductMock() {
        let product = ProductModel.mock()
        XCTAssertFalse(product.name.isEmpty)
        XCTAssertEqual(product.price, 100)
        XCTAssertEqual(product.stock, 10)
        XCTAssertFalse(product.isDisabled)
    }
}
