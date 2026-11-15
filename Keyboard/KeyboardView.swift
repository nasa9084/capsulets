import SwiftUI
import UIKit

/// キーボード全体。上が変換候補、下が 5 列 × 4 段のキー
struct KeyboardView: View {
    @ObservedObject var state: KeyboardState
    /// 押している最中のフリックキー（上に重ねて、伸びる様子を描く）
    @State private var flick: FlickPreview?

    static let coordinateSpace = "keyboard"

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
        .coordinateSpace(name: Self.coordinateSpace)
        .overlay(alignment: .topLeading) {
            FlickBubble(preview: flick)
                .allowsHitTesting(false)
        }
    }

    // MARK: - 左の列（タブ切替・カーソル・キーボード切替）

    private var leftColumn: some View {
        VStack(spacing: Self.spacing) {
            FunctionKey(label: .text(state.tab == .kana ? "☆123" : "あいう")) {
                state.playSound(.function)
                state.tab = state.tab == .kana ? .number : .kana
            }
            FunctionKey(label: .symbol("arrow.left")) { state.moveCursor(-1) }
            FunctionKey(label: .symbol("keyboard.chevron.compact.down")) { state.dismissKeyboard() }
            FunctionKey(label: .symbol("globe")) { state.nextKeyboard() }
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
                    FlickKey(labels: KanaTable.wa, preview: $flick) { state.inputKana($0) }
                    FlickKey(labels: KanaTable.punctuation, title: "、。?!", preview: $flick) { state.inputKana($0) }
                }
            case .number:
                ForEach(0..<3, id: \.self) { row in
                    keyRow(KanaTable.numberRows[row]) { state.inputDirect($0) }
                }
                HStack(spacing: Self.spacing) {
                    FlickKey(labels: KanaTable.brackets, title: "()[]", preview: $flick) { state.inputDirect($0) }
                    FlickKey(labels: KanaTable.zero, preview: $flick) { state.inputDirect($0) }
                    FlickKey(labels: KanaTable.dots, title: ".,-/", preview: $flick) { state.inputDirect($0) }
                }
            }
        }
    }

    private func keyRow(_ keys: [[String]], action: @escaping (String) -> Void) -> some View {
        HStack(spacing: Self.spacing) {
            ForEach(keys, id: \.self) { labels in
                FlickKey(labels: labels, preview: $flick, action: action)
            }
        }
    }

    // MARK: - 右の列（削除・カーソル・空白・改行）

    private var rightColumn: some View {
        VStack(spacing: Self.spacing) {
            RepeatKey(systemImage: "delete.left") { state.delete() }
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

/// フリックで 5 方向の文字を入れるキー
struct FlickKey: View {
    /// [中央, 左, 上, 右, 下]
    let labels: [String]
    /// キーに出す文字（省略すると中央の文字）
    var title: String?
    @Binding var preview: FlickPreview?
    let action: (String) -> Void

    private static let threshold: CGFloat = 16

    var body: some View {
        GeometryReader { geometry in
            KeyFace(color: KeyColor.normal) {
                Text(title ?? labels[0])
                    .font(.system(size: title == nil ? 22 : 17))
            }
            .foregroundStyle(Color.primary)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let direction = flickDirection(value.translation)
                        let next = FlickPreview(
                            frame: geometry.frame(in: .named(KeyboardView.coordinateSpace)),
                            direction: direction,
                            text: labels[direction]
                        )
                        if preview != next {
                            preview = next
                        }
                    }
                    .onEnded { value in
                        let text = labels[flickDirection(value.translation)]
                        preview = nil
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
/// 押しただけなら濃い色のキー、フリックするとその方向の隣のマスまで伸びる
struct FlickBubble: View {
    let preview: FlickPreview?

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let preview {
                let cell = targetCell(preview)
                let shape = preview.frame.union(cell)
                let isFlicked = preview.direction != 0
                RoundedRectangle(cornerRadius: 6)
                    .fill(isFlicked ? Color.accentColor : KeyColor.pressed)
                    .shadow(color: .black.opacity(0.3), radius: isFlicked ? 3 : 0, x: 0, y: 1)
                    .frame(width: shape.width, height: shape.height)
                    .position(x: shape.midX, y: shape.midY)
                Text(preview.text)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(isFlicked ? Color.white : Color.primary)
                    .position(x: cell.midX, y: cell.midY)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(.easeOut(duration: 0.08), value: preview)
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

/// 押しっぱなしで繰り返すキー（削除）
struct RepeatKey: View {
    let systemImage: String
    let action: () -> Void

    @State private var isPressed = false
    @State private var timer: Timer?

    var body: some View {
        KeyFace(color: isPressed ? KeyColor.functionPressed : KeyColor.function) {
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
