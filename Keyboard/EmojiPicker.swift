import CoreText
import SwiftUI
import UIKit

enum EmojiCategory: CaseIterable {
    case recent
    case smileys
    case animals
    case food
    case activities
    case travel
    case objects
    case symbols
    case flags

    var title: String {
        switch self {
        case .recent: "最近使った項目"
        case .smileys: "スマイリーと人々"
        case .animals: "動物と自然"
        case .food: "食べ物と飲み物"
        case .activities: "アクティビティ"
        case .travel: "旅行と場所"
        case .objects: "物"
        case .symbols: "記号"
        case .flags: "旗"
        }
    }

    /// タブに出す SF Symbols の名前
    var symbol: String {
        switch self {
        case .recent: "clock"
        case .smileys: "face.smiling"
        case .animals: "pawprint"
        case .food: "fork.knife"
        case .activities: "soccerball"
        case .travel: "car"
        case .objects: "lightbulb"
        case .symbols: "number"
        case .flags: "flag"
        }
    }

    fileprivate var data: String {
        switch self {
        case .recent: ""
        case .smileys: EmojiData.smileys
        case .animals: EmojiData.animals
        case .food: EmojiData.food
        case .activities: EmojiData.activities
        case .travel: EmojiData.travel
        case .objects: EmojiData.objects
        case .symbols: EmojiData.symbols
        case .flags: EmojiData.flags
        }
    }
}

/// 絵文字の一覧の状態（選んでいるカテゴリと、最近使った絵文字）
final class EmojiModel: ObservableObject {
    @Published private(set) var category: EmojiCategory = .smileys
    @Published private(set) var emojis: [String] = []

    private static let recentsKey = "keyboard.recentEmoji"
    private static let maxRecents = 32

    private var recents = UserDefaults.standard.stringArray(forKey: recentsKey) ?? []
    /// この iOS で表示できる絵文字（カテゴリを開いたときに調べて覚えておく）
    private var supported: [EmojiCategory: [String]] = [:]

    /// 表示できるかを調べた結果を手放す（メモリが足りないときやキーボードを閉じたとき）
    func releaseCache() {
        supported = [:]
        if !emojis.isEmpty {
            emojis = []
        }
    }

    /// 一覧を開く。最近使った絵文字があればそこから始める
    func open() {
        select(recents.isEmpty ? .smileys : .recent)
    }

    func select(_ category: EmojiCategory) {
        self.category = category
        emojis = category == .recent ? recents : supportedEmojis(in: category)
    }

    /// 使った絵文字を覚える。表示中の並びは、押した絵文字が動かないようにそのままにする
    func record(_ emoji: String) {
        recents.removeAll { $0 == emoji }
        recents.insert(emoji, at: 0)
        recents = Array(recents.prefix(Self.maxRecents))
        UserDefaults.standard.set(recents, forKey: Self.recentsKey)
    }

    private func supportedEmojis(in category: EmojiCategory) -> [String] {
        if let cached = supported[category] {
            return cached
        }
        let all = category.data.split(separator: " ").map(String.init)
        let filtered = all.filter(Self.isSupported)
        // 判定がうまく働かず全部落ちたときは、絞り込まずに出す
        let result = filtered.isEmpty ? all : filtered
        supported[category] = result
        return result
    }

    /// この iOS で 1 文字の絵文字として表示できるか。
    /// 新しい絵文字は、古い iOS では複数の絵文字に分かれたり「?」になったりするので外す
    static func isSupported(_ emoji: String) -> Bool {
        let text = NSAttributedString(string: emoji, attributes: [.font: UIFont.systemFont(ofSize: 20)])
        let line = CTLineCreateWithAttributedString(text)
        guard CTLineGetGlyphCount(line) == 1,
              let run = (CTLineGetGlyphRuns(line) as? [CTRun])?.first,
              let font = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName as String]
        else { return false }
        // swiftlint:disable:next force_cast
        let name = CTFontCopyPostScriptName(font as! CTFont) as String
        return name.contains("Emoji")
    }
}

/// キーボードの中に出す絵文字の一覧。下のタブでカテゴリを切り替え、「戻る」で元のキーに戻る
struct EmojiPicker: View {
    let state: KeyboardState
    @ObservedObject var model: EmojiModel

    private static let headerHeight: CGFloat = 28
    private static let tabBarHeight: CGFloat = 44
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 8)

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: model.category.symbol)
                Text(model.category.title)
                Spacer()
            }
            .font(.system(size: 14))
            .foregroundStyle(Color.secondary)
            .padding(.horizontal, 12)
            .frame(height: Self.headerHeight)

            Group {
                if model.emojis.isEmpty {
                    Text("最近使った絵文字はありません")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView(.vertical) {
                        LazyVGrid(columns: columns, spacing: 2) {
                            ForEach(model.emojis, id: \.self) { emoji in
                                Button {
                                    state.inputEmoji(emoji)
                                } label: {
                                    Text(emoji)
                                        .font(.system(size: 30))
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 42)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                    }
                    // カテゴリを変えたら一番上から見せる
                    .id(model.category)
                }
            }
            .background(Color(uiColor: .systemBackground))

            HStack(spacing: 0) {
                Button {
                    state.closeEmoji()
                } label: {
                    Text("戻る").font(.system(size: 15))
                }
                .buttonStyle(KeyButtonStyle(color: KeyColor.function, pressedColor: KeyColor.functionPressed))
                .frame(width: 52)

                ForEach(EmojiCategory.allCases, id: \.self) { category in
                    Button {
                        state.playSound(.function)
                        model.select(category)
                    } label: {
                        Image(systemName: category.symbol)
                            .font(.system(size: 18))
                            .foregroundStyle(Color.primary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(model.category == category ? KeyColor.function : Color.clear)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                DeleteKey(
                    flick: state.flick,
                    onDelete: { state.delete() },
                    onDeleteToLineStart: { state.deleteToLineStart() },
                    onDeleteToLineEnd: { state.deleteToLineEnd() }
                )
                .frame(width: 52)
            }
            .frame(height: Self.tabBarHeight)
            .background(Color(uiColor: .systemBackground))
        }
    }
}
