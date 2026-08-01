//
//  HomeAlphabetIndex.swift
//  BrewDesk
//
//  目录字母索引：悬停高亮，点击跳转到对应首字母。
//

import SwiftUI

struct HomeAlphabetIndex: View {
    let letters: [String]
    let onSelect: (String) -> Void

    @State private var hoveredLetter: String?

    var body: some View {
        VStack(spacing: 1) {
            ForEach(letters, id: \.self) { letter in
                Text(letter.uppercased())
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(hoveredLetter == letter ? .primary : .secondary)
                    .frame(width: 18, height: 13)
                    .background {
                        if hoveredLetter == letter {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color.accentColor.opacity(0.16))
                        }
                    }
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        hoveredLetter = hovering ? letter : nil
                    }
                    .onTapGesture {
                        onSelect(letter)
                    }
                    .accessibilityLabel("跳到以 \(letter.uppercased()) 开头的软件包")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityIdentifier("index-\(letter)")
            }
        }
        .accessibilityElement(children: .contain)
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .onTapGesture { /* 吞掉空白区域的点击，避免穿透到列表行 */ }
        .padding(.vertical, 4)
        .padding(.horizontal, 2)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(.thinMaterial)
                .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
        }
        .padding(.trailing, 4)
        .help("点击跳转到以该字母开头的软件包")
    }
}
