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
                Section {
                    NavigationLink("定型文") {
                        SnippetListView()
                    }
                }
                Section("使い始め方") {
                    Text("1. 設定 → 一般 → キーボード → キーボード → 新しいキーボードを追加 で「Capsulets」を選ぶ")
                    Text("2. 文字を打つ画面で地球儀キーを長押しして「Kana」に切り替える")
                    Text("3. タイプ音と定型文を使うには、同じ画面で「Kana」→「フルアクセスを許可」をオンにする（このキーボードは通信しません）")
                    Button("設定を開く") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
                Section("キーの使い方") {
                    Text("かなキーはフリックで入力（例: 「あ」を左にフリックで「い」）")
                    Text("「゛゜小」で直前の文字を小書き・濁点・半濁点に切り替え")
                    Text("入力中は候補をタップして変換。「確定」はひらがなのまま確定")
                    Text("削除キーは長押しで連続削除。左フリックで行頭まで、上フリックで行末まで削除（行末では改行を1つ削除）")
                    Text("地球儀キーは長押しで定型文のリスト。指をすべらせて選び、離すと入力")
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
