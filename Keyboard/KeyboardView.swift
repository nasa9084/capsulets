import SwiftUI
import UIKit

/// キーボード全体。上が変換候補、下が 5 列 × 4 段のキー
struct KeyboardView: View {
    @ObservedObject var state: KeyboardState

    static let coordinateSpace = "keyboard"

    static let candidateBarHeight: CGFloat = 36
    static let keyHeight: CGFloat = 50
    static let spacing: CGFloat = 6
    static let padding: CGFloat = 4
    static let totalHeight: CGFloat = candidateBarHeight + keyHeight * 4 + spacing * 3 + padding * 2

    var body: some View {
        Group {
            if state.isEmojiVisible {
                EmojiPicker(state: state, model: state.emoji)
            } else {
                keys
            }
        }
        .frame(height: Self.totalHeight)
        .coordinateSpace(name: Self.coordinateSpace)
        .overlay(alignment: .topLeading) {
            FlickBubble(model: state.flick)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .topLeading) {
            SnippetMenu(model: state.snippetMenu)
                .allowsHitTesting(false)
        }
    }

    /// 変換候補とキー
    private var keys: some View {
        VStack(spacing: 0) {
            CandidateBar(state: state)
                .frame(height: Self.candidateBarHeight)
            GeometryReader { geometry in
                switch state.layout {
                case .flick:
                    let unit = (geometry.size.width - Self.spacing * 4) / 5
                    HStack(alignment: .top, spacing: Self.spacing) {
                        leftColumn(keyboardWidth: geometry.size.width + Self.padding * 2, unit: unit)
                            .frame(width: unit)
                        centerKeys.frame(width: unit * 3 + Self.spacing * 2)
                        rightColumn.frame(width: unit)
                    }
                case .qwerty:
                    QwertyKeys(state: state, width: geometry.size.width)
                }
            }
            .padding(Self.padding)
        }
    }

    // MARK: - 左の列（タブ切替・カーソル・キーボード切替と定型文）

    private func leftColumn(keyboardWidth: CGFloat, unit: CGFloat) -> some View {
        VStack(spacing: Self.spacing) {
            FunctionKey(label: .symbol("keyboard.chevron.compact.down")) { state.dismissKeyboard() }
            FunctionKey(label: .symbol("arrow.left")) { state.moveCursor(-1) }
            // 押すと切り替わる先のタブ名を出す
            FunctionKey(label: .text(state.nextTab.title)) { state.switchTab() }
            GlobeKey(
                menu: state.snippetMenu,
                keyboardWidth: keyboardWidth,
                menuMinX: Self.padding + unit + Self.spacing,
                onTap: { state.toggleLayout() },
                onMenuOpen: { state.playSound(.function) },
                onSelect: { state.insertSnippet($0) }
            )
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
                    FlickKey(labels: KanaTable.wa, flick: state.flick) { state.inputKana($0) }
                    FlickKey(labels: KanaTable.punctuation, title: "、。?!", flick: state.flick) { state.inputKana($0) }
                }
            case .english:
                ForEach(0..<3, id: \.self) { row in
                    keyRow(KanaTable.englishRows[row], showsAllLabels: true) { state.inputDirect($0) }
                }
                HStack(spacing: Self.spacing) {
                    TapKey(label: "a/A") { state.toggleCaseOfLastCharacter() }
                    FlickKey(labels: KanaTable.quotes, title: "'\"()", flick: state.flick) { state.inputDirect($0) }
                    FlickKey(labels: KanaTable.englishPunctuation, title: ".,?!", flick: state.flick) {
                        state.inputDirect($0)
                    }
                }
            case .number:
                ForEach(0..<3, id: \.self) { row in
                    keyRow(KanaTable.numberRows[row], showsFlickHints: true) { state.inputDirect($0) }
                }
                HStack(spacing: Self.spacing) {
                    FlickKey(labels: KanaTable.brackets, title: "()[]", flick: state.flick) { state.inputDirect($0) }
                    FlickKey(labels: KanaTable.zero, showsFlickHints: true, flick: state.flick) {
                        state.inputDirect($0)
                    }
                    FlickKey(labels: KanaTable.dots, title: ".,-/", flick: state.flick) { state.inputDirect($0) }
                }
            }
        }
    }

    /// showsAllLabels: キーに全方向の文字を並べて出す（英字の "abc" など）
    private func keyRow(
        _ keys: [[String]], showsAllLabels: Bool = false, showsFlickHints: Bool = false,
        action: @escaping (String) -> Void
    ) -> some View {
        HStack(spacing: Self.spacing) {
            ForEach(keys, id: \.self) { labels in
                FlickKey(
                    labels: labels, title: showsAllLabels ? labels.joined() : nil,
                    showsFlickHints: showsFlickHints, flick: state.flick, action: action
                )
            }
        }
    }

    // MARK: - 右の列（削除・カーソル・空白・改行）

    private var rightColumn: some View {
        VStack(spacing: Self.spacing) {
            DeleteKey(
                flick: state.flick,
                onDelete: { state.delete() },
                onDeleteToLineStart: { state.deleteToLineStart() },
                onDeleteToLineEnd: { state.deleteToLineEnd() }
            )
            FunctionKey(label: .symbol("arrow.right")) { state.moveCursor(1) }
            FunctionKey(label: .text("空白")) { state.space() }
            FunctionKey(label: .text(state.isComposing ? "確定" : "改行"), isProminent: state.isComposing) {
                state.enter()
            }
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
                            state.tapCandidate(index)
                        } label: {
                            Text(candidate.text)
                                .font(.system(size: 18))
                                .foregroundStyle(Color.primary)
                                .lineLimit(1)
                                .padding(.horizontal, 12)
                                .frame(maxHeight: .infinity)
                        }
                        .buttonStyle(.plain)
                        .id(index)
                    }
                }
                .padding(.horizontal, 4)
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
    /// 押している文字キー
    static let pressed = dynamic(
        light: UIColor(red: 0.62, green: 0.66, blue: 0.72, alpha: 1), dark: UIColor(white: 0.72, alpha: 1)
    )
    /// 押している機能キー（iOS 標準と同じく、明るくなる）
    static let functionPressed = dynamic(light: UIColor(white: 1, alpha: 1), dark: UIColor(white: 0.45, alpha: 1))

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

/// 押している最中のフリックキーの様子
struct FlickPreview: Equatable {
    /// キーの位置（キーボード全体の座標）
    var frame: CGRect
    /// 0: 中央, 1: 左, 2: 上, 3: 右, 4: 下
    var direction: Int
    /// 指を離すと入る文字
    var text: String
}

/// 押している最中のキーの様子を、重ねて描く表示（FlickBubble）に伝える。
/// キーボード全体を描き直さずに済むよう、KeyboardState とは別に持つ
final class FlickModel: ObservableObject {
    @Published var preview: FlickPreview?

    func update(_ next: FlickPreview?) {
        if preview != next {
            preview = next
        }
    }
}

/// フリックで 5 方向の文字を入れるキー
struct FlickKey: View {
    /// [中央, 左, 上, 右, 下]
    let labels: [String]
    /// キーに出す文字（省略すると中央の文字）
    var title: String?
    /// 中央の文字の下に、フリックで入る文字を小さく並べて出す
    var showsFlickHints = false
    let flick: FlickModel
    let action: (String) -> Void

    /// これ以上指を動かしたらフリックとみなす距離
    static let threshold: CGFloat = 16

    var body: some View {
        GeometryReader { geometry in
            KeyFace(color: KeyColor.normal) {
                if showsFlickHints {
                    VStack(spacing: 0) {
                        Text(labels[0])
                            .font(.system(size: 22))
                        Text(labels.dropFirst().joined(separator: " "))
                            .font(.system(size: 10))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                } else {
                    Text(title ?? labels[0])
                        .font(.system(size: title == nil ? 22 : 17))
                }
            }
            .foregroundStyle(Color.primary)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let direction = flickDirection(value.translation)
                        flick.update(FlickPreview(
                            frame: geometry.frame(in: .named(KeyboardView.coordinateSpace)),
                            direction: direction,
                            text: labels[direction]
                        ))
                    }
                    .onEnded { value in
                        let text = labels[flickDirection(value.translation)]
                        flick.update(nil)
                        action(text)
                    }
            )
        }
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

/// 押しているフリックキーの上に重ねる表示。
/// 押すと青くなり、フリックするとその方向の隣のマスまで伸びる
struct FlickBubble: View {
    @ObservedObject var model: FlickModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let preview = model.preview {
                let cell = targetCell(preview)
                let shape = preview.frame.union(cell)
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.accentColor)
                    .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                    .frame(width: shape.width, height: shape.height)
                    .position(x: shape.midX, y: shape.midY)
                Text(preview.text)
                    .font(.system(size: preview.text.count > 1 ? 20 : 28, weight: .medium))
                    .foregroundStyle(Color.white)
                    .position(x: cell.midX, y: cell.midY)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// 入る文字を出すマス（フリックした方向の隣。中央ならキー自身）
    private func targetCell(_ preview: FlickPreview) -> CGRect {
        let frame = preview.frame
        let stepX = frame.width + KeyboardView.spacing
        let stepY = frame.height + KeyboardView.spacing
        var cell: CGRect
        switch preview.direction {
        case 1: cell = frame.offsetBy(dx: -stepX, dy: 0)
        case 2: cell = frame.offsetBy(dx: 0, dy: -stepY)
        case 3: cell = frame.offsetBy(dx: stepX, dy: 0)
        case 4: cell = frame.offsetBy(dx: 0, dy: stepY)
        default: cell = frame
        }
        // 一番上の段を上にフリックしたとき、キーボードの外にはみ出さないようにする
        let top: CGFloat = 2
        if cell.minY < top {
            cell = CGRect(x: cell.minX, y: top, width: cell.width, height: cell.maxY - top)
        }
        return cell
    }
}

/// 文字キーと同じ見た目で、タップだけのキー
struct TapKey: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label).font(.system(size: 17))
        }
        .buttonStyle(KeyButtonStyle(color: KeyColor.normal, pressedColor: KeyColor.pressed))
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
            switch label {
            case .text(let text):
                Text(text).font(.system(size: 15))
            case .symbol(let name):
                Image(systemName: name).font(.system(size: 18))
            }
        }
        .buttonStyle(
            isProminent
                ? KeyButtonStyle(
                    color: Color.accentColor, pressedColor: Color.accentColor.opacity(0.6), textColor: Color.white
                )
                : KeyButtonStyle(color: KeyColor.function, pressedColor: KeyColor.functionPressed)
        )
    }
}

/// キーの形のボタン。押している間は色を変える
struct KeyButtonStyle: ButtonStyle {
    let color: Color
    let pressedColor: Color
    var textColor = Color.primary

    func makeBody(configuration: Configuration) -> some View {
        KeyFace(color: configuration.isPressed ? pressedColor : color) {
            configuration.label
        }
        .foregroundStyle(textColor)
    }
}

/// 削除キー。タップで 1 文字、押しっぱなしで連続、左フリックで行頭まで、上フリックで行末まで削除する
struct DeleteKey: View {
    let flick: FlickModel
    let onDelete: () -> Void
    let onDeleteToLineStart: () -> Void
    let onDeleteToLineEnd: () -> Void

    @State private var isPressed = false
    /// 押しっぱなしの連続削除が始まったか（始まっていたら、指を離したときには消さない）
    @State private var didRepeat = false
    @State private var timer: Timer?

    var body: some View {
        GeometryReader { geometry in
            KeyFace(color: KeyColor.function) {
                Image(systemName: "delete.left").font(.system(size: 18))
            }
            .foregroundStyle(Color.primary)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let direction = flickDirection(value.translation)
                        if !isPressed {
                            isPressed = true
                            didRepeat = false
                            startRepeat()
                        }
                        if direction != 0 {
                            stopRepeat()
                        }
                        flick.update(FlickPreview(
                            frame: geometry.frame(in: .named(KeyboardView.coordinateSpace)),
                            direction: direction,
                            text: direction == 1 ? "行頭" : direction == 2 ? "行末" : "⌫"
                        ))
                    }
                    .onEnded { value in
                        stopRepeat()
                        isPressed = false
                        flick.update(nil)
                        switch flickDirection(value.translation) {
                        case 1: onDeleteToLineStart()
                        case 2: onDeleteToLineEnd()
                        default:
                            if !didRepeat {
                                onDelete()
                            }
                        }
                    }
            )
        }
        .onDisappear(perform: stopRepeat)
    }

    /// 0: フリックなし, 1: 左, 2: 上
    private func flickDirection(_ translation: CGSize) -> Int {
        let (dx, dy) = (translation.width, translation.height)
        guard max(abs(dx), abs(dy)) >= FlickKey.threshold else { return 0 }
        if abs(dx) > abs(dy) {
            return dx < 0 ? 1 : 0
        }
        return dy < 0 ? 2 : 0
    }

    /// 少し待ってから連続で削除する
    private func startRepeat() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { _ in
            didRepeat = true
            onDelete()
            timer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { _ in
                onDelete()
            }
        }
    }

    private func stopRepeat() {
        timer?.invalidate()
        timer = nil
    }
}
