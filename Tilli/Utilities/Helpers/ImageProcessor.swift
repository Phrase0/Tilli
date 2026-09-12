//
//  ImageProcessor.swift
//  Tilli
//
//  本機圖片處理：尺寸正規化、裁切為正方形、壓縮編碼。
//  （由原 Data/Sync/ImageSyncService.swift 抽出，移除所有雲端上傳/下載邏輯）
//
//  重建同步時，上傳端只要沿用這裡的 ImageType 規格即可，
//  不要再各自寫一套壓縮參數。見 ARCHITECTURE.md §4（imageData 為 X 純本機）。
//

import UIKit

// MARK: - 圖片類型

/// 圖片類型，決定處理規格
enum ImageType {
    /// QR Code：512x512px PNG 無損
    case qrCode
    /// 縮圖（產品、頭貼）：200x200px JPEG 壓縮
    case thumbnail

    /// 目標尺寸
    var targetSize: CGFloat {
        switch self {
        case .qrCode: return 512
        case .thumbnail: return 200
        }
    }

    /// 是否使用 PNG 格式
    var usePNG: Bool {
        switch self {
        case .qrCode: return true
        case .thumbnail: return false
        }
    }

    /// JPEG 壓縮品質（僅 thumbnail 使用）
    var compressionQuality: CGFloat {
        switch self {
        case .qrCode: return 1.0  // PNG 不需要
        case .thumbnail: return 0.8
        }
    }

    /// Content-Type（重建同步時上傳 Storage 用）
    var contentType: String {
        switch self {
        case .qrCode: return "image/png"
        case .thumbnail: return "image/jpeg"
        }
    }

    /// 檔案副檔名（重建同步時上傳 Storage 用）
    var fileExtension: String {
        switch self {
        case .qrCode: return "png"
        case .thumbnail: return "jpg"
        }
    }
}

// MARK: - 圖片處理

enum ImageProcessor {

    /// 處理圖片供本地儲存（調整尺寸 + 轉換格式）
    /// - Parameters:
    ///   - image: 原始圖片
    ///   - type: 圖片類型
    /// - Returns: 處理後的圖片資料
    static func processForLocal(_ image: UIImage, type: ImageType) -> Data? {
        let resized = resizeToSquare(image, targetSize: type.targetSize)
        return type.usePNG
            ? resized.pngData()
            : resized.jpegData(compressionQuality: type.compressionQuality)
    }

    /// 調整圖片為正方形並縮放到指定尺寸
    static func resizeToSquare(_ image: UIImage, targetSize: CGFloat) -> UIImage {
        // 先把 imageOrientation 烘進實際像素資料。image.size 是照 imageOrientation 校正過的「顯示」尺寸，
        // 但 .cgImage 是原始像素資料、不認得 imageOrientation；直接拿校正過的座標去裁未校正的像素，
        // 遇到非 .up 方向的照片（例如直式拍攝的相機照片）就會裁到錯的位置。這裡先正規化，讓兩邊座標系統一致。
        let normalized = normalizedOrientation(image)
        let size = normalized.size

        // 1. 先裁切為正方形
        let squareSize = min(size.width, size.height)
        let origin = CGPoint(
            x: (size.width - squareSize) / 2,
            y: (size.height - squareSize) / 2
        )
        let cropRect = CGRect(origin: origin, size: CGSize(width: squareSize, height: squareSize))

        guard let cgImage = normalized.cgImage?.cropping(to: cropRect) else {
            return normalized
        }

        let croppedImage = UIImage(cgImage: cgImage, scale: normalized.scale, orientation: .up)

        // 2. 縮放到目標尺寸
        let newSize = CGSize(width: targetSize, height: targetSize)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            croppedImage.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    /// 把 imageOrientation 烘進實際像素資料（重新畫一次），讓 .cgImage 的座標系統跟 .size 一致
    static func normalizedOrientation(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let renderer = UIGraphicsImageRenderer(size: image.size)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }
}
