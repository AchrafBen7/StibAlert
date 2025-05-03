//
//  CustomInputField.swift
//  StibAlert
//
//  Created by studentehb on 16/04/2025.
//
import SwiftUI

import SwiftUI

struct CustomInputField: View {
    let placeholder: String
    @Binding var text: String
    var isMultiline: Bool = false
    
    init(placeholder: String, text: Binding<String>, isMultiline: Bool = false) {
        self.placeholder = placeholder
        self._text = text
        self.isMultiline = isMultiline
        
        // Fixe important : rendre le fond du TextEditor transparent
        UITextView.appearance().backgroundColor = .clear
    }
    
    var body: some View {
        if isMultiline {
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .foregroundColor(.white.opacity(0.6))
                        .padding(.top, 14)
                        .padding(.leading, 18)
                }
                
                TextEditor(text: $text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color(hex: "#23236F")) // bleu foncé
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    .font(.body)
            }
            .frame(minHeight: 120, alignment: .top)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(hex: "#23236F"), lineWidth: 1)
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
