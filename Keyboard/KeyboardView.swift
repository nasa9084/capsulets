import SwiftUI
import UIKit

/// キーボード全体。上が変換候補、下が 5 列 × 4 段のキー
struct KeyboardView: View {
    @ObservedObject var state: KeyboardState

    static let candidateBarHeight: CGFloat = 44
    static let keyHeight: CGFloat = 50
    static let spacing: CGFloat = 6
    static let padding: CGFloat = 4
    static let totalHeight: CGFloat = candidateBarHeight + keyHeight * 4 + spacing * 3 + padding * 2

    var body: some View {
        VStack(spacing: 0) {
            CandidateBar(state: state)
                .frame(height: Self.candidateBarHeight)
            GeometryReader { geometry in
                let unit = (geometry.size.width - Self.spacing * 4) / 5
                HStack(alignment: .top, spacing: Self.spacing) {
                    leftColumn.frame(width: unit)
                    centerKeys.frame(width: unit * 3 + Self.spacing * 2)
                    rightColumn.frame(width: unit)
                }
            }
            .padding(Self.padding)
        }
        .frame(height: Self.totalHeight)
    }

    // MARK: - 左の列（タブ切替・カーソル・キーボード切替）

    private var leftColumn: some View {
        VStack(spacing: Self.spacing) {
            FunctionKey(label: .text(state.tab == .kana ? "☆123" : "あいう")) {
                state.tab = state.tab == .kana ? .number : .kana
            }
            FunctionKey(label: .symbol("arrow.left")) { state.moveCursor(-1) }
            FunctionKey(label: .symbol("arrow.right")) { state.moveCursor(1) }
            if state.needsGlobeKey {
                FunctionKey(label: .symbol("globe")) { state.nextKeyboard() }
            } else {
                FunctionKey(label: .symbol("keyboard.chevron.compact.down")) { state.dismissKeyboard() }
            }
        }
    }

    // MARK: - 中央の 3 列（フリックキー）

    private var centerKeys: some View {
        VStack(spacing: Self.spacing) {
            switch state.tab {
            case .kana:
                ForEach(0..<3, id: \.self) { row in
                    keyRow(KanaTable.kanaRows[row]) { state.inputKana($0) }
                }
                HStack(spacing: Self.spacing) {
                    TapKey(label: "゛゜小") { state.modifyLastCharacter() }
                    FlickKey(labels: KanaTable.wa) { state.inputKana($0) }
                    FlickKey(labels: KanaTable.punctuation, title: "、。?!") { state.inputKana($0) }
                }
            case .number:
                ForEach(0..<3, id: \.self) { row in
                    keyRow(KanaTable.numberRows[row]) { state.inputDirect($0) }
                }
                HStack(spacing: Self.spacing) {
                    FlickKey(labels: KanaTable.brackets, title: "()[]") { state.inputDirect($0) }
                    FlickKey(labels: KanaTable.zero) { state.inputDirect($0) }
                    FlickKey(labels: KanaTable.dots, title: ".,-/") { state.inputDirect($0) }
                }
            }
        }
    }

    private func keyRow(_ keys: [[String]], action: @escaping (String) -> Void) -> some View {
        HStack(spacing: Self.spacing) {
            ForEach(keys, id: \.self) { labels in
                FlickKey(labels: labels, action: action)
            }
        }
    }

    // MARK: - 右の列（削除・空白・改行）

    private var rightColumn: some View {
        VStack(spacing: Self.spacing) {
            RepeatKey(systemImage: "delete.left") { state.delete() }
            FunctionKey(label: .text(state.isComposing ? "次候補" : "空白")) { state.space() }
            FunctionKey(label: .text(state.isComposing ? "確定" : "改行"), isProminent: state.isComposing) {
                state.enter()
            }
            .frame(height: Self.keyHeight * 2 + Self.spacing)
        }
    }
}

// MARK: - 変換候補

struct CandidateBar: View {
    @ObservedObject var state: KeyboardState

    var body: some View {
        ScrollViewReader { reader in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(Array(state.candidates.enumerated()), id: \.offset) { index, candidate in
                        Button {
                            state.choose(index)
                        } label: {
                            Text(candidate.text)
                                .font(.system(size: 18))
                                .foregroundStyle(Color.primary)
                                .lineLimit(1)
                                .padding(.horizontal, 12)
                                .frame(maxHeight: .infinity)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(state.selectedIndex == index ? KeyColor.pressed : Color.clear)
                                        .padding(.vertical, 5)
                                )
                        }
                        .buttonStyle(.plain)
                        .id(index)
                    }
                }
                .padding(.horizontal, 4)
            }
            .onChange(of: state.selectedIndex) { _, index in
                if let index {
                    withAnimation { reader.scrollTo(index, anchor: .center) }
                }
            }
            .onChange(of: state.candidates.first?.text) { _, _ in
                // 候補が変わったら先頭に戻す
                reader.scrollTo(0, anchor: .leading)
            }
        }
    }
}

// MARK: - キー

enum KeyColor {
    static let normal = dynamic(light: UIColor(white: 1, alpha: 1), dark: UIColor(white: 0.42, alpha: 1))
    static let function = dynamic(
        light: UIColor(red: 0.67, green: 0.70, blue: 0.75, alpha: 1), dark: UIColor(white: 0.27, alpha: 1)
    )
    static let pressed = dynamic(
        light: UIColor(red: 0.80, green: 0.83, blue: 0.88, alpha: 1), dark: UIColor(white: 0.58, alpha: 1)
    )

    private static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
}

/// キーの見た目（角丸の板と下の影）
struct KeyFace<Content: View>: View {
    let color: Color
    @ViewBuilder let content: Content

    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(color)
            .shadow(color: .black.opacity(0.3), radius: 0, x: 0, y: 1)
            .overlay { content }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
    }
}

/// フリックで 5 方向の文字を入れるキー
struct FlickKey: View {
    /// [中央, 左, 上, 右, 下]
    let labels: [String]
    /// キーに出す文字（省略すると中央の文字）
    var title: String?
    let action: (String) -> Void

    /// 押している間の方向（nil は押していない）
    @State private var direction: Int?

    private static let threshold: CGFloat = 16

    var body: some View {
        KeyFace(color: direction == nil ? KeyColor.normal : KeyColor.pressed) {
            if let direction {
                Text(labels[direction])
                    .font(.system(size: 26, weight: .medium))
            } else {
                Text(title ?? labels[0])
                    .font(.system(size: title == nil ? 22 : 17))
            }
        }
        .foregroundStyle(Color.primary)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    direction = flickDirection(value.translation)
                }
                .onEnded { value in
                    let text = labels[flickDirection(value.translation)]
                    direction = nil
                    action(text)
                }
        )
    }

    private func flickDirection(_ translation: CGSize) -> Int {
        let (dx, dy) = (translation.width, translation.height)
        guard max(abs(dx), abs(dy)) >= Self.threshold else { return 0 }
        let index: Int
        if abs(dx) > abs(dy) {
            index = dx < 0 ? 1 : 3
        } else {
            index = dy < 0 ? 2 : 4
        }
        // 割り当てのない方向は中央の文字にする
        return labels[index].isEmpty ? 0 : index
    }
}

/// 文字キーと同じ見た目で、タップだけのキー
struct TapKey: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            KeyFace(color: KeyColor.normal) {
                Text(label).font(.system(size: 17))
            }
        }
        .buttonStyle(KeyButtonStyle())
    }
}

/// 機能キー（タブ切替・空白・改行など）
struct FunctionKey: View {
    enum Label {
        case text(String)
        case symbol(String)
    }

    let label: Label
    var isProminent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            KeyFace(color: isProminent ? Color.accentColor : KeyColor.function) {
                switch label {
                case .text(let text):
                    Text(text).font(.system(size: 15))
                case .symbol(let name):
                    Image(systemName: name).font(.system(size: 18))
                }
            }
            .foregroundStyle(isProminent ? Color.white : Color.primary)
        }
        .buttonStyle(KeyButtonStyle())
    }
}

/// 押している間、少し暗くする
struct KeyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.primary)
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// 押しっぱなしで繰り返すキー（削除）
struct RepeatKey: View {
    let systemImage: String
    let action: () -> Void

    @State private var isPressed = false
    @State private var timer: Timer?

    var body: some View {
        KeyFace(color: isPressed ? KeyColor.pressed : KeyColor.function) {
            Image(systemName: systemImage).font(.system(size: 18))
        }
        .foregroundStyle(Color.primary)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isPressed else { return }
                    isPressed = true
                    action()
                    // 少し待ってから連続で実行する
                    timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { _ in
                        timer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { _ in
                            action()
                        }
                    }
                }
                .onEnded { _ in
                    isPressed = false
                    timer?.invalidate()
                    timer = nil
                }
        )
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }
}
