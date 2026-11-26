import SwiftUI

/// キーボードの使い始め方と、試し打ちの欄
struct KeyboardGuideView: View {
    @State private var text = ""
    @State private var deleteFlickDistance = KeyboardSettings.deleteFlickDistance
    @State private var accentColor = KeyboardSettings.accentColor
    @State private var wideAlignment = KeyboardSettings.wideAlignment

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
                    NavigationLink("キーボードのログ") {
                        KeyboardLogView()
                    }
                }
                Section {
                    Picker("キーボードの色", selection: $accentColor) {
                        ForEach(KeyboardSettings.accentColorChoices, id: \.hex) { choice in
                            Label {
                                Text(choice.title)
                            } icon: {
                                Image(systemName: "circle.fill")
                                    .foregroundStyle(Color(hex: choice.hex))
                            }
                            .tag(choice.hex)
                        }
                    }
                    .pickerStyle(.navigationLink)
                } footer: {
                    Text("フリックしたときの表示、変換候補の選択、定型文の選択、確定キーの色。次にキーボードを出したときから変わります。")
                }
                .onChange(of: accentColor) { _, color in
                    KeyboardSettings.accentColor = color
                }
                Section {
                    Picker("広い画面での位置", selection: $wideAlignment) {
                        ForEach(KeyboardSettings.WideAlignment.allCases, id: \.self) { alignment in
                            Text(alignment.title).tag(alignment)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("広い画面での位置")
                } footer: {
                    Text("iPhone Duo の内側の画面など横に広いときは、キーボードを iPhone くらいの幅にして、ここで選んだ側に寄せます。次にキーボードを出したときから変わります。")
                }
                .onChange(of: wideAlignment) { _, alignment in
                    KeyboardSettings.wideAlignment = alignment
                }
                Section {
                    Picker("行削除フリックの感度", selection: $deleteFlickDistance) {
                        ForEach(KeyboardSettings.deleteFlickDistanceChoices, id: \.distance) { choice in
                            Text(choice.title).tag(choice.distance)
                        }
                    }
                } footer: {
                    Text("削除キーを左・上にフリックして行頭・行末まで消すとき、どれだけ指を動かしたら反応するか。鈍めにするほど、長く動かさないと反応しません。")
                }
                .onChange(of: deleteFlickDistance) { _, distance in
                    KeyboardSettings.deleteFlickDistance = distance
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
                    Text("入力中に「変換」を押すと候補の一覧が広がる。「変換」「次候補」で選び、「確定」で確定。⇤ ⇥ で変換する範囲を調整")
                    Text("入力中に矢印左・右で、変換する範囲を縮める・伸ばす。候補をタップするとその部分だけ確定")
                    Text("QWERTY の英字では、打ちかけの単語の続きが候補に出る。タップで単語と空白を入力")
                    Text("QWERTY の「.」キーは、左フリックで「,」、上で「:」、下で「;」")
                    Text("QWERTY の数字のページにある顔のキーで絵文字の一覧。「戻る」で元に戻る")
                    Text("削除キーは長押しで連続削除。左フリックで行頭まで、上フリックで行末まで削除（行末では改行を1つ削除）")
                    Text("地球儀キーはタップでフリックと QWERTY の切り替え、長押しで定型文のリスト。指をすべらせて選び、離すと入力")
                    Text("「あいう / ABC / ☆123」のキーで、日本語 → 英語 → 数字 の順に切り替え（QWERTY は英語と数字のみ）")
                    Text("フリックの英語は、シフトキーを押してから打つと大文字（もう一度押すと大文字のまま）")
                    Text("「:thi」のように「:」のあとに絵文字の名前を打つと、合う絵文字が候補に出る。タップで絵文字に変わる")
                }
            }
            .navigationTitle("キーボード")
        }
    }
}

#Preview {
    KeyboardGuideView()
}
