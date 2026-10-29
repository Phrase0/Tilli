//
//  BundleImageView.swift
//  Tilli
//
//  套餐照片：有本機照片（BundleImageStore）就顯示，否則與無照片商品相同的 placeholder。
//

import SwiftUI

struct BundleImageView: View {
    let bundleId: UUID
    var contentMode: SwiftUI.ContentMode = .fill

    var body: some View {
        if let image = BundleImageStore.load(for: bundleId) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: contentMode)
        } else {
            EntityImageView(
                imageData: nil,
                imageURL: nil,
                entityId: bundleId,
                entityType: .product,
                contentMode: contentMode
            )
        }
    }
}
