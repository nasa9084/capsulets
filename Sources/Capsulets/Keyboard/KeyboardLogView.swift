import SwiftUI

/// キーボードの動きの記録を見る（うまく起動しないときの調査用）
struct KeyboardLogView: View {
    @State private var entries: [KeyboardLog.Entry] = []
    @State private var isConfirmingClear = false

    var body: some View {
        List {
            Section {
                if entries.isEmpty {
                    Text("記録はまだありません。キーボードの「フルアクセスを許可」がオンでないと記録されません。")
                        .foregroundStyle(.secondary)
                }
                ForEach(entries) { entry in
                    Text(entry.line)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(entry.line.contains("⚠️") ? Color.red : Color.primary)
                        .textSelection(.enabled)
                }
            } footer: {
                Text("新しい順。[ ] の中はその時点のキーボードのメモリ使用量です。キーボードは使うメモリが多すぎると iOS に止められます。")
            }
        }
        .navigationTitle("キーボードのログ")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: KeyboardLog.text()) {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(entries.isEmpty)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("消去", systemImage: "trash", role: .destructive) {
                    isConfirmingClear = true
                }
                .disabled(entries.isEmpty)
            }
        }
        .refreshable { reload() }
        .onAppear(perform: reload)
        .confirmationDialog("ログを消去しますか？", isPresented: $isConfirmingClear, titleVisibility: .visible) {
            Button("消去", role: .destructive) {
                KeyboardLog.clear()
                reload()
            }
        }
    }

    private func reload() {
        entries = KeyboardLog.load()
    }
}
