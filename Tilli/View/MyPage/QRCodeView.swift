//
//  MerchantQRCodeView.swift
//  Tilli
//
//  Created by Peiyun on 2025/9/17.
//

import SwiftUI

struct QRCodeView: View {

    @EnvironmentObject var qrCodeDataManager: QRCodeRepository
    @EnvironmentObject var authManager: AuthenticationManager
    @State private var showingImagePicker = false
    @State private var tempSelectedImage: UIImage?
    @State private var showDeleteAlert = false

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                VStack(spacing: 40) {
                    Spacer()

                    ZStack(alignment: .topTrailing) {
                        Button {
                            showingImagePicker = true
                        } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                                    .fill(DesignSystem.ColorToken.cardSurface)
                                    .frame(width: 300, height: 300)
                                    .shadow(
                                        color: DesignSystem.Shadow.cardColor,
                                        radius: DesignSystem.Shadow.cardRadius,
                                        x: DesignSystem.Shadow.cardX,
                                        y: DesignSystem.Shadow.cardY
                                    )

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
                                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.md))
                                } else {
                                    VStack(spacing: DesignSystem.Spacing.md) {
                                        RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                                            .stroke(style: StrokeStyle(lineWidth: 3, dash: [10]))
                                            .foregroundColor(DesignSystem.ColorToken.muted.opacity(0.4))
                                            .frame(width: 100, height: 100)
                                            .overlay(
                                                Image(systemName: "plus")
                                                    .font(.system(size: 40))
                                                    .foregroundColor(DesignSystem.ColorToken.muted.opacity(0.6))
                                            )

                                        VStack(spacing: DesignSystem.Spacing.xxs) {
                                            // 加入收款 QR Code
                                            Text("qrCodeAddTitle")
                                                .font(.system(size: 18, weight: .medium))
                                                .foregroundColor(DesignSystem.ColorToken.muted)
                                            // 點擊選擇照片
                                            Text("qrCodeAddHint")
                                                .font(DesignSystem.Typography.body)
                                                .foregroundColor(DesignSystem.ColorToken.muted.opacity(0.7))
                                        }
                                    }
                                }
                            }
                        }
                        .buttonStyle(PlainButtonStyle())

                        if qrCodeDataManager.qrCode != nil {
                            Button {
                                showDeleteAlert = true
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 30))
                                    .foregroundColor(DesignSystem.ColorToken.muted)
                                    .background(
                                        Circle()
                                            .fill(DesignSystem.ColorToken.cardSurface)
                                            .frame(width: 24, height: 24)
                                    )
                                    .offset(x: 8, y: -8)
                            }
                            .padding(DesignSystem.Spacing.xs)
                        }
                    }

                    Spacer()
                }
            }
            // 我的收款碼
            .navigationTitle("qrCodeNavTitle")
            .navigationBarTitleDisplayMode(.large)
        }
        .background(DesignSystem.ColorToken.paper)
        .sheet(isPresented: $showingImagePicker) {
            CustomImagePicker(image: $tempSelectedImage, isPresented: $showingImagePicker)
        }
        .onChange(of: tempSelectedImage) {
            if let image = tempSelectedImage {
                var model = QRCodeModel(
                    id: qrCodeDataManager.qrCode?.id ?? UUID(),
                    imageData: nil,
                    imageURL: nil,
                    createdAt: qrCodeDataManager.qrCode?.createdAt ?? Date()
                )
                model.image = image
                qrCodeDataManager.saveQRCode(model)
                tempSelectedImage = nil

                if authManager.isLoggedIn {
                    Task {
                        do {
                            let imageURL = try await ImageSyncService.shared.uploadQRCodeImage(image)
                            guard authManager.isLoggedIn else { return }
                            await MainActor.run {
                                qrCodeDataManager.updateQRCodeImageURL(imageURL)
                            }
                        } catch {
                            print("QRCode image upload failed: \(error)")
                        }
                    }
                }
            }
        }
        // 確定要刪除此收款碼嗎？
        .alert("qrCodeDeleteAlert", isPresented: $showDeleteAlert) {
            // 取消
            Button("commonCancel", role: .cancel) { }
            // 刪除
            Button("commonDelete", role: .destructive) {
                qrCodeDataManager.deleteQRCode()
            }
        } message: {
            // 刪除後將無法復原
            Text("qrCodeDeleteMessage")
        }
    }
}
