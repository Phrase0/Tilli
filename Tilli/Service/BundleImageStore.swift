//
//  BundleImageStore.swift
//  Tilli
//
//  套餐照片的本機存檔（設計 §3：圖檔不放進 bundlesData，只存本機）。
//  路徑：Application Support/BundleImages/<bundleId>.jpg
//

import UIKit

enum BundleImageStore {

    /// 讀過的圖留在記憶體，收銀頁每次重繪不必再讀檔；寫入／刪除時一併更新
    private static let cache = NSCache<NSUUID, UIImage>()

    /// 縮成縮圖規格（與商品照片相同）後寫檔。失敗回傳 false。
    @discardableResult
    static func save(_ image: UIImage, for bundleId: UUID) -> Bool {
        guard let data = ImageProcessor.processForLocal(image, type: .thumbnail),
              let url = fileURL(for: bundleId, createDirectory: true) else { return false }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            print("BundleImageStore.save failed: \(error)")
            return false
        }
        if let stored = UIImage(data: data) {
            cache.setObject(stored, forKey: bundleId as NSUUID)
        }
        return true
    }

    static func load(for bundleId: UUID) -> UIImage? {
        if let cached = cache.object(forKey: bundleId as NSUUID) { return cached }
        guard let url = fileURL(for: bundleId, createDirectory: false),
              let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else { return nil }
        cache.setObject(image, forKey: bundleId as NSUUID)
        return image
    }

    static func delete(for bundleId: UUID) {
        cache.removeObject(forKey: bundleId as NSUUID)
        guard let url = fileURL(for: bundleId, createDirectory: false),
              FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// 複製場次時把照片帶到新套餐（來源沒有照片則不做事）
    static func copy(from source: UUID, to destination: UUID) {
        guard let sourceURL = fileURL(for: source, createDirectory: false),
              FileManager.default.fileExists(atPath: sourceURL.path),
              let destinationURL = fileURL(for: destination, createDirectory: true) else { return }
        delete(for: destination)
        do {
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        } catch {
            print("BundleImageStore.copy failed: \(error)")
        }
    }

    private static func fileURL(for bundleId: UUID, createDirectory: Bool) -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let directory = base.appendingPathComponent("BundleImages", isDirectory: true)
        if createDirectory {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory.appendingPathComponent("\(bundleId.uuidString).jpg")
    }
}
