//
//  AvatarPickerSheetView.swift
//  wishmaker
//
//  Created by Alexandra Lazareva on 27.04.2026.

import SwiftUI

struct AvatarPickerSheetView: View {
    
    let copy: AppCopy
    let selectedAvatar: String
    let options: [String]
    let onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(options, id: \.self) { symbol in
                    Button {
                        onSelect(symbol)
                        dismiss()
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: symbol)
                                .font(.system(size: 20, weight: .semibold))
                                .frame(width: 34, height: 34)
                                .foregroundStyle(AppColors.color(AppColors.primaryText))
                                .background(
                                    Circle()
                                        .fill(AppColors.color(AppColors.cardFill))
                                )

                            Text(symbol.replacingOccurrences(of: ".", with: " "))
                                .foregroundStyle(AppColors.color(AppColors.primaryText))

                            Spacer()

                            if symbol == selectedAvatar {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(AppColors.color(AppColors.accent))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(AppColors.color(AppColors.appBackground))
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppColors.color(AppColors.appBackground))
            .navigationTitle(copy.chooseAvatar)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(copy.close) {
                        dismiss()
                    }
                }
            }
        }
    }
}
