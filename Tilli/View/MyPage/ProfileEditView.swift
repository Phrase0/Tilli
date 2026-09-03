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

    @StateObject private var viewModel = ProfileEditViewModel()
    @State private var showingImagePicker = false

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
                            if let image = viewModel.selectedImage {
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

                        TextField(String.localized("profileEditNamePlaceholder"), text: $viewModel.name)
                            .font(DesignSystem.Typography.body)
                            .padding(DesignSystem.Spacing.md)
                            .background(DesignSystem.ColorToken.cardSurface)
                            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.sm))

                        if !viewModel.isNameValid && !viewModel.name.isEmpty {
                            Text("profileEditNameEmpty")
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.ColorToken.alertRed)
                        }
                    }
                    .padding(.horizontal, DesignSystem.Spacing.lg)

                    if let error = viewModel.errorMessage {
                        Text(error)
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.ColorToken.alertRed)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, DesignSystem.Spacing.lg)
                    }

                    Spacer(minLength: 40)

                    Button {
                        Task {
                            if await viewModel.saveProfile(authManager: authManager) {
                                dismiss()
                            }
                        }
                    } label: {
                        HStack {
                            if viewModel.isSaving {
                                ProgressView()
                                    .tint(DesignSystem.ColorToken.onButtonFilled)
                            }
                            Text(isNewUser
                                 ? String.localized("profileEditDone")
                                 : String.localized("profileEditSave"))
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DesignSystem.Spacing.md)
                        .background(viewModel.canSave ? DesignSystem.ColorToken.buttonFilled : DesignSystem.ColorToken.muted)
                        .foregroundColor(viewModel.canSave ? DesignSystem.ColorToken.onButtonFilled : DesignSystem.ColorToken.cardSurface)
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.md))
                    }
                    .disabled(!viewModel.canSave)
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    .padding(.bottom, DesignSystem.Spacing.lg)
                }
            }
        }
        .navigationTitle(isNewUser
                         ? String.localized("profileEditCreateTitle")
                         : String.localized("profileEditEditTitle"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            if !isNewUser {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("commonCancel") {
                        dismiss()
                    }
                    .disabled(viewModel.isSaving)
                }
            }
        }
        .sheet(isPresented: $showingImagePicker) {
            CustomImagePicker(image: $viewModel.selectedImage, isPresented: $showingImagePicker)
        }
        .onAppear {
            if !isNewUser, let user = authManager.currentUser {
                viewModel.loadExistingName(from: user)
            }
        }
        .interactiveDismissDisabled(viewModel.isSaving || isNewUser)
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
}
