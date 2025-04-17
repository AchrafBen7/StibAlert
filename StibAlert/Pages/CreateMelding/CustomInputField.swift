//
//  CustomInputField.swift
//  StibAlert
//
//  Created by studentehb on 16/04/2025.
//
import SwiftUI


struct CustomInputField: View {
    let placeholder: String
    @Binding var text: String
    var isMultiline: Bool = false
    
    var body: some View {
        if isMultiline {
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .foregroundColor(.gray.opacity(0.6))
                        .padding(.top, 14)
                        .padding(.leading, 18)
                }
                
                TextEditor(text: $text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color.white)
                    .cornerRadius(10)
                    .font(.body)
                    .opacity(1) // Important : pas de transparence
            }
            .frame(minHeight: 120, alignment: .top)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
        } else {
            TextField(placeholder, text: $text)
                .padding()
                .background(Color.white)
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
        }
    }
}
