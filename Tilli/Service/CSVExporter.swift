//
//  CSVExporter.swift
//  Tilli
//
//  Created by Peiyun on 2026/9/12.
//
//  CSV 匯出的共用流程：暫存目錄、檔名淨化、時間戳、寫入，以及 CSV 欄位逸出。
//

import Foundation

enum CSVExporter {

    /// 把 CSV 內容寫進暫存檔並回傳 URL。
    ///
    /// 檔名格式：`<label>_<淨化後的場次名>_<yyyyMMdd_HHmmss>.csv`
    /// - Parameters:
    ///   - content: 已組好的 CSV 全文
    ///   - label: 已本地化的檔案標籤（例如「庫存總覽」）
    ///   - eventTitle: 場次名稱，會自動淨化掉檔名不合法的字元
    static func write(content: String, label: String, eventTitle: String) -> URL {
        let fileName = "\(label)_\(sanitizeFileName(eventTitle))_\(DateFormatter.fileTimestamp.string(from: Date())).csv"
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            print("🔴 CSV 寫入失敗（\(label)）: \(error)")
        }

        return fileURL
    }

    /// CSV 欄位逸出（RFC 4180）。
    ///
    /// 含逗號／引號／換行時整欄加引號，內部引號變成兩個。使用者資料保持原樣
    /// （不把逗號替換成全形），商品名稱含這些字元時 CSV 也不會壞掉。
    static func escape(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") else {
            return field
        }
        return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    /// 組一列 CSV（每個欄位都逸出，以逗號相連，結尾換行）
    static func row(_ fields: [String]) -> String {
        fields.map(escape).joined(separator: ",") + "\n"
    }

    /// 淨化檔名中不合法或容易出問題的字元
    private static func sanitizeFileName(_ name: String) -> String {
        name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
    }
}
