import SwiftUI

/// QWERTY 配列のキー。英語と数字記号を切り替えて使う（日本語入力はフリック配列で行う）
struct QwertyKeys: View {
    @ObservedObject var state: KeyboardState
    /// キーを並べる領域の幅
    let width: CGFloat

    private var spacing: CGFloat { KeyboardView.spacing }
    /// 文字キー 1 つの幅（1 段に 10 個）
    private var unit: CGFloat { (width - spacing * 9) / 10 }
    /// 一番下の段の機能キー（切り替え・地球儀・改行）の幅
    private var bottomSideWidth: CGFloat { unit * 1.25 }

    private static let letters = [
        ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
        ["a", "s", "d", "f", "g", "h", "j", "k", "l", "."],
        ["z", "x", "c", "v", "b", "n", "m"],
    ]
    private static let symbols = [
        [
            ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
            ["-", "/", ":", ";", "(", ")", "¥", "&", "@", "\""],
            [".", ",", "?", "!", "'", "`"],
        ],
        [
            ["[", "]", "{", "}", "#", "%", "^", "*", "+", "="],
            ["_", "\\", "|", "~", "<", ">", "$", "€", "£", "…"],
            [".", ",", "?", "!", "'", "§", "†"],
        ],
    ]

    private var rows: [[String]] {
        state.tab == .number ? Self.symbols[state.symbolPage] : Self.letters
    }

    var body: some View {
        VStack(spacing: spacing) {
            letterRow(rows[0])
            letterRow(rows[1])
            HStack(spacing: spacing) {
                modeKey
                letterRow(rows[2])
                if state.tab == .number, state.symbolPage == 0 {
                    Button {
                        state.openEmoji()
                    } label: {
                        Image(systemName: "face.smiling").font(.system(size: 20))
                    }
                    .buttonStyle(KeyButtonStyle(color: KeyColor.normal, pressedColor: KeyColor.pressed))
                    .frame(width: unit)
                }
                DeleteKey(
                    flick: state.flick,
                    onDelete: { state.delete() },
                    onDeleteToLineStart: { state.deleteToLineStart() },
                    onDeleteToLineEnd: { state.deleteToLineEnd() }
                )
            }
            HStack(spacing: spacing) {
                FunctionKey(label: .text(state.tab == .number ? "ABC" : "123")) { state.switchTab() }
                    .frame(width: bottomSideWidth)
                GlobeKey(
                    menu: state.snippetMenu,
                    keyboardWidth: width + KeyboardView.padding * 2,
                    menuMinX: KeyboardView.padding + (bottomSideWidth + spacing) * 2,
                    onTap: { state.toggleLayout() },
                    onMenuOpen: { state.playSound(.function) },
                    onSelect: { state.insertSnippet($0) }
                )
                .frame(width: bottomSideWidth)
                Button {
                    state.space()
                } label: {
                    Text("space").font(.system(size: 16))
                }
                .buttonStyle(KeyButtonStyle(color: KeyColor.normal, pressedColor: KeyColor.pressed))
                // 矢印 2 つは、すき間を詰めてひとまとまりに見せる
                HStack(spacing: 1) {
                    FunctionKey(label: .symbol("arrow.left")) { state.moveCursor(-1) }
                    FunctionKey(label: .symbol("arrow.right")) { state.moveCursor(1) }
                }
                .frame(width: unit * 1.9)
                FunctionKey(label: .symbol("return")) { state.enter() }
                    .frame(width: bottomSideWidth)
            }
        }
    }

    private func letterRow(_ keys: [String]) -> some View {
        HStack(spacing: spacing) {
            ForEach(keys, id: \.self) { key in
                let label = state.shift == .off ? key : key.uppercased()
                LetterKey(label: label, flick: state.flick) { state.inputQwerty(key) }
                    .frame(width: unit)
            }
        }
    }

    /// 3 段目の左端。文字のときはシフト、数字記号のときは記号のページ切り替え
    @ViewBuilder private var modeKey: some View {
        if state.tab == .number {
            FunctionKey(label: .text(state.symbolPage == 0 ? "#+=" : "123")) { state.toggleSymbolPage() }
        } else {
            FunctionKey(label: .symbol(shiftSymbol)) { state.toggleShift() }
        }
    }

    private var shiftSymbol: String {
        switch state.shift {
        case .off: "shift"
        case .once: "shift.fill"
        case .locked: "capslock.fill"
        }
    }
}

/// タップで 1 文字入れるキー。押している間、上に伸びて文字を大きく見せる
struct LetterKey: View {
    let label: String
    let flick: FlickModel
    let action: () -> Void

    var body: some View {
        GeometryReader { geometry in
            KeyFace(color: KeyColor.normal) {
                Text(label).font(.system(size: 22))
            }
            .foregroundStyle(Color.primary)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        flick.update(FlickPreview(
                            frame: geometry.frame(in: .named(KeyboardView.coordinateSpace)),
                            direction: 2,
                            text: label
                        ))
                    }
                    .onEnded { _ in
                        flick.update(nil)
                        action()
                    }
            )
        }
    }
}
