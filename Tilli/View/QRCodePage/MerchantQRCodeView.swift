//
//  EPaymentView.swift
//  Tilli
//
//  Created by Peiyun on 2025/9/17.
//

import SwiftUI

struct MerchantQRCodeView: View {
    
    @EnvironmentObject var qrCodeDataManager: QRCodeDataManager
    @State private var isLinePayLinked = false
    @State private var showingImagePicker = false
    @State private var tempSelectedImage: UIImage?
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // QR Code Section
                VStack(spacing: 40) {
                    Spacer()
                
                        // QR Code Container
                        Button(action: {
                            showingImagePicker = true
                        }) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(Color.white)
                                    .frame(width: 300, height: 300)
                                    .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 6)
                        
                                if let qrImage = qrCodeDataManager.qrCodeImage {
                                    Image(uiImage: qrImage)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
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

                    Spacer()
                }

                // Line Pay Button
                VStack(spacing: 12) {
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                isLinePayLinked.toggle()
                            }
                        }) {
                            HStack {
                                if isLinePayLinked {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 18))
                                    Text("Line Pay 已連結")
                                } else {
                                    Text("連結 Line Pay")
                                }
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(
                                isLinePayLinked ? Color.green : Color(red: 0/255, green: 195/255, blue: 0/255)
                            )
                            .cornerRadius(30)
                        }
                        .animation(.easeInOut(duration: 0.3), value: isLinePayLinked)
                }
                .padding()
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
                qrCodeDataManager.saveQRCode(image)
                tempSelectedImage = nil
            }
        }
    }
}
