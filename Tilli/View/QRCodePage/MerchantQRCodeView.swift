//
//  EPaymentView.swift
//  Tilli
//
//  Created by Peiyun on 2025/9/17.
//

import SwiftUI

struct MerchantQRCodeView: View {

    @EnvironmentObject var qrCodeDataManager: QRCodeRepository
    @EnvironmentObject var authManager: AuthenticationManager
    @State private var showingImagePicker = false
    @State private var tempSelectedImage: UIImage?
    @State private var showDeleteAlert = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // QR Code Section
                VStack(spacing: 40) {
                    Spacer()

                        // QR Code Container
                        ZStack(alignment: .topTrailing) {
                            Button(action: {
                                showingImagePicker = true
                            }) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 20)
                                        .fill(Color.white)
                                        .frame(width: 300, height: 300)
                                        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 6)

                                    if let qrCode = qrCodeDataManager.qrCode,
                                       (qrCode.imageData != nil || qrCode.imageURL != nil) {
                                        SyncableImageView(
                                            imageData: qrCode.imageData,
                                            imageURL: qrCode.imageURL,
                                            entityId: qrCode.id,
                                            entityType: .qrCode,
                                            contentMode: .fit
                                        )
                                        .frame(width: 280, height: 280)
                                        .clipShape(RoundedRectangle(cornerRadius: 16))
                                    } else {
                                        VStack(spacing: 16) {
                                            RoundedRectangle(cornerRadius: 16)
                                                .stroke(style: StrokeStyle(lineWidth: 3, dash: [10]))
                                                .foregroundColor(.gray.opacity(0.4))
                                                .frame(width: 100, height: 100)
                                                .overlay(
                                                    Image(systemName: "plus")
                                                        .font(.system(size: 40))
                                                        .foregroundColor(.gray.opacity(0.6))
                                                )

                                            VStack(spacing: 6) {
                                                Text("加入收款 QR Code")
                                                    .font(.system(size: 18, weight: .medium))
                                                    .foregroundColor(.gray)
                                                Text("點擊選擇照片")
                                                    .font(.system(size: 16))
                                                    .foregroundColor(.gray.opacity(0.7))
                                            }
                                        }
                                    }
                                }
                            }
                            .buttonStyle(PlainButtonStyle())

                            // 刪除按鈕（只在有 QR Code 時顯示）
                            if qrCodeDataManager.qrCode != nil {
                                Button(action: {
                                    showDeleteAlert = true
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 30))
                                        .foregroundColor(.gray)
                                        .background(
                                            Circle()
                                                .fill(Color.white)
                                                .frame(width: 24, height: 24)
                                        )
                                        .offset(x: 8, y: -8)
                                }
                                .padding(8)
                            }
                        }

                    Spacer()
                }
            }
            .navigationTitle("我的收款碼")
            .navigationBarTitleDisplayMode(.large)
        }
        .background(Color(.systemGroupedBackground))
        .sheet(isPresented: $showingImagePicker) {
            CustomImagePicker(image: $tempSelectedImage, isPresented: $showingImagePicker)
        }
        .onChange(of: tempSelectedImage) {
            if let image = tempSelectedImage {
                // 沿用現有 id 和 createdAt（UUID 不變，只更新圖片內容）
                var model = QRCodeModel(
                    id: qrCodeDataManager.qrCode?.id ?? UUID(),
                    imageData: nil,
                    imageURL: nil,
                    createdAt: qrCodeDataManager.qrCode?.createdAt ?? Date()
                )
                model.image = image  // 512x512 PNG 無損處理，存入 imageData
                qrCodeDataManager.saveQRCode(model)
                tempSelectedImage = nil

                // 有帳號才上傳 Storage，Guest 直接存本地
                if authManager.isLoggedIn {
                    Task {
                        do {
                            let imageURL = try await ImageSyncService.shared.uploadQRCodeImage(image)
                            // 確認上傳完成時使用者仍在登入狀態
                            guard authManager.isLoggedIn else { return }
                            await MainActor.run {
                                qrCodeDataManager.updateQRCodeImageURL(imageURL)
                            }
                        } catch {
                            // imageData 仍在本地，不影響當前裝置顯示
                            print("❌ QRCode 圖片上傳失敗: \(error)")
                        }
                    }
                }
            }
        }
        .alert("確定要刪除此收款碼嗎？", isPresented: $showDeleteAlert) {
            Button("取消", role: .cancel) { }
            Button("刪除", role: .destructive) {
                qrCodeDataManager.deleteQRCode()
            }
        } message: {
            Text("刪除後將無法復原")
        }
    }
}
