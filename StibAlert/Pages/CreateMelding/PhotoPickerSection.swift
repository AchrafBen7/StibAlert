//
//  PhotoPickerSection.swift
//  StibAlert
//
//  Created by studentehb on 01/05/2025.
//

import SwiftUI

struct PhotoPickerSection: View {
    @Binding var selectedUIImage: UIImage?
    @Binding var showImagePicker: Bool
    @Binding var useCamera: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Photo (facultatif)")
                .font(.subheadline)
                .foregroundColor(.gray)

            if let image = selectedUIImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 150)
                    .cornerRadius(12)
                    .clipped()

                Button("Supprimer la photo") {
                    selectedUIImage = nil
                }
                .foregroundColor(.red)
                .font(.caption)
            } else {
                Button(action: {
                    showImagePicker = true
                }) {
                    HStack {
                        Image(systemName: "camera.fill")
                        Text("Prendre ou choisir une photo")
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.white)
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )
                }
            }
        }
    }
}
