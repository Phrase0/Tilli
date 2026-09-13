//
//  CSVExporterTests.swift
//  TilliTests
//
//  Created by Peiyun on 2026/9/13.
//
//  對應 FEATURE_PLAN_V1.md §2.6（B5）與測試清單 U13。
//

import XCTest
@testable import Tilli

final class CSVExporterTests: XCTestCase {

    // MARK: - escape（U13）

    func testPlainFieldIsUnchanged() {
        XCTAssertEqual(CSVExporter.escape("大福"), "大福")
        XCTAssertEqual(CSVExporter.escape(""), "")
        XCTAssertEqual(CSVExporter.escape("100"), "100")
    }

    func testCommaIsQuotedNotReplaced() {
        // ⭐ 改動前是把逗號偷換成全形「，」—— 那是竄改使用者資料
        XCTAssertEqual(CSVExporter.escape("大福,紅豆"), "\"大福,紅豆\"")
        XCTAssertFalse(CSVExporter.escape("大福,紅豆").contains("，"))
    }

    func testQuoteIsDoubledAndFieldQuoted() {
        // RFC 4180：欄位內的引號要變成兩個，整欄再加引號
        XCTAssertEqual(CSVExporter.escape("他說\"好\""), "\"他說\"\"好\"\"\"")
    }

    func testNewlineIsQuoted() {
        XCTAssertEqual(CSVExporter.escape("第一行\n第二行"), "\"第一行\n第二行\"")
        XCTAssertEqual(CSVExporter.escape("第一行\r第二行"), "\"第一行\r第二行\"")
    }

    func testCommaAndQuoteTogether() {
        XCTAssertEqual(
            CSVExporter.escape("大福,紅豆\"特價\""),
            "\"大福,紅豆\"\"特價\"\"\""
        )
    }

    // MARK: - row

    func testRowEscapesEveryFieldAndEndsWithNewline() {
        let row = CSVExporter.row(["大福,紅豆", "100", "他說\"好\""])

        XCTAssertEqual(row, "\"大福,紅豆\",100,\"他說\"\"好\"\"\"\n")
        XCTAssertTrue(row.hasSuffix("\n"))
    }

    func testEmptyRow() {
        XCTAssertEqual(CSVExporter.row([]), "\n")
    }

    // MARK: - write（檔名與內容）

    func testWriteProducesReadableFileWithExpectedName() throws {
        let content = "a,b\n1,2\n"
        let url = CSVExporter.write(content: content, label: "庫存總覽", eventTitle: "週末市集")

        addTeardownBlock { try? FileManager.default.removeItem(at: url) }

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), content)

        let fileName = url.lastPathComponent
        XCTAssertTrue(fileName.hasPrefix("庫存總覽_週末市集_"), "檔名開頭應為 <標籤>_<場次名>_")
        XCTAssertTrue(fileName.hasSuffix(".csv"))
    }

    func testWriteSanitizesIllegalFileNameCharacters() throws {
        let url = CSVExporter.write(content: "x", label: "交易明細", eventTitle: "2026/09/13:市集\\春")

        addTeardownBlock { try? FileManager.default.removeItem(at: url) }

        let fileName = url.lastPathComponent
        XCTAssertFalse(fileName.contains("/"))
        XCTAssertFalse(fileName.contains(":"))
        XCTAssertFalse(fileName.contains("\\"))
        XCTAssertTrue(fileName.contains("2026-09-13-市集-春"))
    }

    func testWriteUsesFileTimestampFormat() throws {
        let url = CSVExporter.write(content: "x", label: "標籤", eventTitle: "場次")

        addTeardownBlock { try? FileManager.default.removeItem(at: url) }

        // 檔名尾段應為 yyyyMMdd_HHmmss（8 碼 + 底線 + 6 碼）
        let stem = url.deletingPathExtension().lastPathComponent
        let timestamp = String(stem.suffix(15))
        XCTAssertEqual(timestamp.count, 15)
        XCTAssertEqual(timestamp[timestamp.index(timestamp.startIndex, offsetBy: 8)], "_")
        XCTAssertTrue(
            timestamp.filter { $0 != "_" }.allSatisfy(\.isNumber),
            "時間戳應只有數字與一個底線，實際：\(timestamp)"
        )
    }
}
