import SwiftUI

/// キーボードの使い始め方と、試し打ちの欄
struct KeyboardGuideView: View {
    @State private var text = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("試し打ち") {
                    TextEditor(text: $text)
                        .frame(minHeight: 140)
                    Button("消去", role: .destructive) { text = "" }
                        .disabled(text.isEmpty)
                }
                Section("使い始め方") {
                    Text("1. 設定 → 一般 → キーボード → キーボード → 新しいキーボードを追加 で「Capsulets」を選ぶ")
                    Text("2. 文字を打つ画面で地球儀キーを長押しして「Kana」に切り替える")
                    Text("3. タイプ音を鳴らすには、同じ画面で「Kana」→「フルアクセスを許可」をオンにする（このキーボードは通信しません）")
                    Button("設定を開く") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
                Section("キーの使い方") {
                    Text("かなキーはフリックで入力（例: 「あ」を左にフリックで「い」）")
                    Text("「゛゜小」で直前の文字を小書き・濁点・半濁点に切り替え")
                    Text("入力中は「次候補」で候補を選び、「確定」で確定。候補をタップしても確定")
                    Text("「☆123」で数字と記号に切り替え。英字は地球儀キーで標準キーボードへ")
                }
            }
            .navigationTitle("キーボード")
        }
    }
}

#Preview {
    KeyboardGuideView()
}
