//
//  StatusToast.swift
//  BrewDesk
//

import SwiftUI

struct StatusToast: View {
    let message: String
    var isError: Bool = false
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            // Left accent bar
            RoundedRectangle(cornerRadius: 2)
                .fill(isError ? Color.red : Color.green)
                .frame(width: 4)
                .padding(4)

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(isError ? Color.red : Color.green)
                Text(message)
                    .font(.callout)
                    .textSelection(.enabled)
                    .frame(maxWidth: 480, alignment: .leading)
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(12)
        }
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .fixedSize(horizontal: false, vertical: true)
    }
}
