import SwiftUI

/// 地球儀キーの長押しで出す定型文リストの状態
final class SnippetMenuModel: ObservableObject {
    @Published var isVisible = false
    @Published var snippets: [Snippet] = []
    /// 指が乗っている行
    @Published var hovered: Int?
    var keyboardWidth: CGFloat = 0

    func show(keyboardWidth: CGFloat) {
        self.keyboardWidth = keyboardWidth
        // 開くたびに読み直して、アプリでの編集をすぐ反映する
        snippets = Array(SnippetStore.load().prefix(SnippetMenuLayout.maxRows))
        hovered = nil
        isVisible = true
    }

    func hide() {
        isVisible = false
        hovered = nil
    }

    func hover(at point: CGPoint) {
        let index = SnippetMenuLayout.index(at: point, keyboardWidth: keyboardWidth, rows: snippets.count)
        if hovered != index {
            hovered = index
        }
    }
}

/// リストの位置。左の列の右側に、下ぞろえで並べる
enum SnippetMenuLayout {
    static let rowHeight: CGFloat = 38
    static let maxRows = Int((KeyboardView.totalHeight - KeyboardView.padding * 2) / rowHeight)

    static func frame(keyboardWidth: CGFloat, rows: Int) -> CGRect {
        let padding = KeyboardView.padding
        let unit = (keyboardWidth - padding * 2 - KeyboardView.spacing * 4) / 5
        let minX = padding + unit + KeyboardView.spacing
        let height = CGFloat(max(rows, 1)) * rowHeight
        return CGRect(
            x: minX,
            y: KeyboardView.totalHeight - padding - height,
            width: keyboardWidth - padding - minX,
            height: height
        )
    }

    /// 指の位置にある行。リストまで指が来ていなければ nil
    static func index(at point: CGPoint, keyboardWidth: CGFloat, rows: Int) -> Int? {
        guard rows > 0 else { return nil }
        let frame = frame(keyboardWidth: keyboardWidth, rows: rows)
        guard point.x >= frame.minX else { return nil }
        // リストより上まで指が行っても、一番上の行を選んだままにする
        let row = Int(((point.y - frame.minY) / rowHeight).rounded(.down))
        return min(max(row, 0), rows - 1)
    }
}

/// 定型文リスト。指を乗せた行が青くなり、離すと入力される
struct SnippetMenu: View {
    @ObservedObject var model: SnippetMenuModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            if model.isVisible {
                let frame = SnippetMenuLayout.frame(keyboardWidth: model.keyboardWidth, rows: model.snippets.count)
                VStack(spacing: 0) {
                    if model.snippets.isEmpty {
                        row(Text("定型文は Capsulets アプリで登録").foregroundStyle(Color.secondary), isHovered: false)
                    } else {
                        ForEach(Array(model.snippets.enumerated()), id: \.element.id) { index, snippet in
                            row(
                                Text(snippet.text.replacingOccurrences(of: "\n", with: "⏎")),
                                isHovered: model.hovered == index
                            )
                        }
                    }
                }
                .background(Color(uiColor: .systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(color: .black.opacity(0.35), radius: 6, x: 0, y: 2)
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func row(_ text: Text, isHovered: Bool) -> some View {
        text
            .font(.system(size: 16))
            .lineLimit(1)
            .truncationMode(.tail)
            .foregroundStyle(isHovered ? Color.white : Color.primary)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: SnippetMenuLayout.rowHeight)
            .background(isHovered ? Color.accentColor : Color.clear)
    }
}

/// 地球儀キー。タップで次のキーボード、長押しで定型文リスト
struct GlobeKey: View {
    let menu: SnippetMenuModel
    let keyboardWidth: CGFloat
    let onTap: () -> Void
    let onMenuOpen: () -> Void
    let onSelect: (Snippet) -> Void

    @State private var isPressed = false
    @State private var timer: Timer?

    var body: some View {
        KeyFace(color: isPressed ? KeyColor.functionPressed : KeyColor.function) {
            Image(systemName: "globe").font(.system(size: 18))
        }
        .foregroundStyle(Color.primary)
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named(KeyboardView.coordinateSpace))
                .onChanged { value in
                    if !isPressed {
                        isPressed = true
                        timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { _ in
                            menu.show(keyboardWidth: keyboardWidth)
                            onMenuOpen()
                        }
                    }
                    if menu.isVisible {
                        menu.hover(at: value.location)
                    }
                }
                .onEnded { _ in
                    timer?.invalidate()
                    timer = nil
                    isPressed = false
                    if menu.isVisible {
                        let selected = menu.hovered.flatMap { menu.snippets.indices.contains($0) ? menu.snippets[$0] : nil }
                        menu.hide()
                        if let selected {
                            onSelect(selected)
                        }
                    } else {
                        onTap()
                    }
                }
        )
        .onDisappear {
            timer?.invalidate()
            timer = nil
            menu.hide()
        }
    }
}
