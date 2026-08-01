//
//  ProfileEditView.swift
//  Tilli
//
//  Created by Peiyun on 2025/1/21.
//

import SwiftUI
import Kingfisher

struct ProfileEditView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authManager: AuthenticationManager

    let isNewUser: Bool

    @State private var name: String = ""
    @State private var selectedImage: UIImage?
    @State private var showingImagePicker = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var isNameValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var canSave: Bool {
        isNameValid && !isSaving
    }

    var body: some View {
        ZStack {
            DesignSystem.ColorToken.paper
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: DesignSystem.Spacing.lg) {
                    if isNewUser {
                        VStack(spacing: DesignSystem.Spacing.xs) {
                            Text("profileEditSetupTitle")
                                .font(DesignSystem.Typography.title2)

                            Text("profileEditSetupSubtitle")
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.ColorToken.muted)
                        }
                        .padding(.top, DesignSystem.Spacing.lg)
                    }

                    Button {
                        showingImagePicker = true
                    } label: {
                        ZStack {
                            if let image = selectedImage {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 120, height: 120)
                                    .clipShape(Circle())
                            } else if let localImage = authManager.localProfileImage {
                                Image(uiImage: localImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 120, height: 120)
                                    .clipShape(Circle())
                            } else if let photoURL = authManager.currentUser?.photoURL,
                                      let url = URL(string: photoURL) {
                                KFImage(url)
                                    .placeholder { placeholderWithCamera }
                                    .onFailure { _ in }
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 120, height: 120)
                                    .clipShape(Circle())
                            } else {
                                placeholderWithCamera
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                        Text("profileEditNameLabel")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.ColorToken.muted)

                        TextField(String(localized: "profileEditNamePlaceholder"), text: $name)
                            .font(DesignSystem.Typography.body)
                            .padding(DesignSystem.Spacing.md)
                            .background(DesignSystem.ColorToken.cardSurface)
                            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.sm))

                        if !isNameValid && !name.isEmpty {
                            Text("profileEditNameEmpty")
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.ColorToken.alertRed)
                        }
                    }
                    .padding(.horizontal, DesignSystem.Spacing.lg)

                    if let error = errorMessage {
                        Text(error)
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.ColorToken.alertRed)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, DesignSystem.Spacing.lg)
                    }

                    Spacer(minLength: 40)

                    Button {
                        Task {
                            await saveProfile()
                        }
                    } label: {
                        HStack {
                            if isSaving {
                                ProgressView()
                                    .tint(DesignSystem.ColorToken.onButtonFilled)
                            }
                            Text(isNewUser
                                 ? String(localized: "profileEditDone")
                                 : String(localized: "profileEditSave"))
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DesignSystem.Spacing.md)
                        .background(canSave ? DesignSystem.ColorToken.buttonFilled : DesignSystem.ColorToken.muted)
                        .foregroundColor(canSave ? DesignSystem.ColorToken.onButtonFilled : DesignSystem.ColorToken.cardSurface)
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.md))
                    }
                    .disabled(!canSave)
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    .padding(.bottom, DesignSystem.Spacing.lg)
                }
            }
        }
        .navigationTitle(isNewUser
                         ? String(localized: "profileEditCreateTitle")
                         : String(localized: "profileEditEditTitle"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            if !isNewUser {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("commonCancel") {
                        dismiss()
                    }
                    .disabled(isSaving)
                }
            }
        }
        .sheet(isPresented: $showingImagePicker) {
            CustomImagePicker(image: $selectedImage, isPresented: $showingImagePicker)
        }
        .onAppear {
            if !isNewUser, let user = authManager.currentUser {
                name = user.name
            }
        }
        .interactiveDismissDisabled(isSaving || isNewUser)
    }

    private var placeholderWithCamera: some View {
        Circle()
            .fill(DesignSystem.ColorToken.quietFill)
            .frame(width: 120, height: 120)
            .overlay(
                VStack(spacing: DesignSystem.Spacing.xxs) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 30))
                        .foregroundColor(DesignSystem.ColorToken.muted)
                    Text("profileEditAddPhoto")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.ColorToken.muted)
                }
            )
    }

    private func saveProfile() async {
        guard isNameValid else { return }

        isSaving = true
        errorMessage = nil

        do {
            var photoURL: String? = nil

            if let image = selectedImage,
               let uid = authManager.currentUser?.uid {
                photoURL = try await ImageSyncService.shared.uploadProfileImage(image, uid: uid)
            }

            let trimmedName = name.trimmingCharacters(in: .whitespaces)
            let processedImage = selectedImage.map { ImageSyncService.shared.processImage($0, type: .thumbnail) }
            await authManager.updateProfile(name: trimmedName, photoURL: photoURL, localImage: processedImage)

            isSaving = false
            dismiss()

        } catch {
            isSaving = false
            errorMessage = String(localized: "profileEditSaveError \(error.localizedDescription)")
            print("Save profile error: \(error)")
        }
    }
}
