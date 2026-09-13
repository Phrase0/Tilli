//
//  TransactionIndexTests.swift
//  TilliTests
//
//  Created by Peiyun on 2026/9/13.
//
//  對應 FEATURE_PLAN_V1.md §2.1（A1、E1）與 §11 第 1 批的 1.1。
//

import XCTest
@testable import Tilli

final class TransactionIndexTests: XCTestCase {

    private let productA = UUID()
    private let productB = UUID()
    private let categoryJia = UUID()   // 甲
    private let categoryYi = UUID()    // 乙

    // MARK: - 空索引

    func testEmptyIndexAnswersNoToEverything() {
        let index = TransactionIndex(transactions: [])

        XCTAssertFalse(index.hasAnyTransaction)
        XCTAssertEqual(index.transactionCount, 0)
        XCTAssertFalse(index.hasTransaction(productId: productA))
        XCTAssertFalse(index.hasTransaction(categoryId: categoryJia))
    }

    func testStaticEmptyMatchesEmptyInit() {
        XCTAssertFalse(TransactionIndex.empty.hasAnyTransaction)
        XCTAssertEqual(TransactionIndex.empty.transactionCount, 0)
    }

    // MARK: - 基本查詢

    func testIndexFindsSoldProductAndCategory() {
        let item = SummaryItemModel.mock(productId: productA, categoryId: categoryJia)
        let index = TransactionIndex(transactions: [.mock(items: [item])])

        XCTAssertTrue(index.hasAnyTransaction)
        XCTAssertEqual(index.transactionCount, 1)
        XCTAssertTrue(index.hasTransaction(productId: productA))
        XCTAssertTrue(index.hasTransaction(categoryId: categoryJia))

        // 沒賣過的商品與類別一律 false
        XCTAssertFalse(index.hasTransaction(productId: productB))
        XCTAssertFalse(index.hasTransaction(categoryId: categoryYi))
    }

    /// ⭐ A1 的核心：答案只看歷史快照，不隨商品搬移而改變。
    ///
    /// 目前 UI 走不到這個情境（有交易的商品不能改類別，見 §1.1「A1 的可達性」），
    /// 所以這條測試是**唯一**能守住這個行為的方式 —— 也是 Backlog 的
    /// 「開放商品編輯」解禁前必須先綠的護欄。
    func testCategoryAnswerFollowsSnapshotNotCurrentProductCategory() {
        // 商品 A 在「甲」類別時賣掉，交易的 SummaryItem.categoryId 記下的是甲
        let soldItem = SummaryItemModel.mock(productId: productA, categoryId: categoryJia)
        let index = TransactionIndex(transactions: [.mock(items: [soldItem])])

        // 之後 A 被搬到「乙」類別（直接改 ProductModel.categoryId，索引完全不知道這件事）
        var movedProduct = ProductModel.mock(id: productA, categoryId: categoryJia)
        movedProduct.categoryId = categoryYi

        // 「甲曾經賣過東西嗎」→ 有。這是歷史事實，不因商品搬走而改變
        XCTAssertTrue(index.hasTransaction(categoryId: categoryJia))
        // 「乙曾經賣過東西嗎」→ 沒有。A 是搬過去之後才在乙底下的
        XCTAssertFalse(index.hasTransaction(categoryId: categoryYi))
        // 商品層級不受影響
        XCTAssertTrue(index.hasTransaction(productId: movedProduct.id))
    }

    // MARK: - 計數

    func testTransactionCountCountsTransactionsNotItems() {
        let threeItems = [
            SummaryItemModel.mock(productId: productA, categoryId: categoryJia),
            SummaryItemModel.mock(productId: productB, categoryId: categoryJia),
            SummaryItemModel.mock(productId: UUID(), categoryId: categoryYi)
        ]
        let index = TransactionIndex(transactions: [.mock(items: threeItems)])

        XCTAssertEqual(index.transactionCount, 1, "一筆交易含三個項目，仍然只算一筆")
    }

    func testSameProductInMultipleTransactionsIsNotDoubleCounted() {
        let transactions = (0..<3).map { _ in
            TransactionModel.mock(items: [.mock(productId: productA, categoryId: categoryJia)])
        }
        let index = TransactionIndex(transactions: transactions)

        XCTAssertEqual(index.transactionCount, 3)
        XCTAssertTrue(index.hasTransaction(productId: productA))
    }

    // MARK: - 邊界

    func testTransactionWithNoItemsStillCountsAsATransaction() {
        let index = TransactionIndex(transactions: [.mock(items: [])])

        // 「這個場次有交易嗎」→ 有（影響幣別能不能改）
        XCTAssertTrue(index.hasAnyTransaction)
        XCTAssertEqual(index.transactionCount, 1)
        // 但沒有任何商品／類別被賣過
        XCTAssertFalse(index.hasTransaction(productId: productA))
        XCTAssertFalse(index.hasTransaction(categoryId: categoryJia))
    }

    func testMultipleCategoriesInOneTransaction() {
        let items = [
            SummaryItemModel.mock(productId: productA, categoryId: categoryJia),
            SummaryItemModel.mock(productId: productB, categoryId: categoryYi)
        ]
        let index = TransactionIndex(transactions: [.mock(items: items)])

        XCTAssertTrue(index.hasTransaction(categoryId: categoryJia))
        XCTAssertTrue(index.hasTransaction(categoryId: categoryYi))
    }
}
