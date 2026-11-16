import SwiftUI

/// 定型文の登録・並べ替え・削除
struct SnippetListView: View {
    @State private var snippets = SnippetStore.load()
    /// 編集中の定型文（新規のときは空の定型文）
    @State private var editing: Snippet?

    var body: some View {
        List {
            Section {
                ForEach(snippets) { snippet in
                    Button {
                        editing = snippet
                    } label: {
                        Text(snippet.text)
                            .lineLimit(3)
                            .foregroundStyle(Color.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .onDelete { offsets in
                    snippets.remove(atOffsets: offsets)
                }
                .onMove { source, destination in
                    snippets.move(fromOffsets: source, toOffset: destination)
                }
            } footer: {
                Text("キーボードの地球儀キーを長押しするとリストが出ます。そのまま指をすべらせて、入れたい定型文の上で離すと入力されます。リストに出るのは上から\(snippetMenuRows)件です。")
            }
        }
        .overlay {
            if snippets.isEmpty {
                ContentUnavailableView("定型文がありません", systemImage: "text.badge.plus", description: Text("右上の＋で追加します"))
            }
        }
        .navigationTitle("定型文")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("追加", systemImage: "plus") {
                    editing = Snippet(text: "")
                }
            }
        }
        .sheet(item: $editing) { snippet in
            SnippetEditor(snippet: snippet) { edited in
                if let index = snippets.firstIndex(where: { $0.id == edited.id }) {
                    snippets[index] = edited
                } else {
                    snippets.append(edited)
                }
            }
        }
        .onChange(of: snippets) { _, snippets in
            SnippetStore.save(snippets)
        }
    }
}

/// キーボードのリストに出せる件数（キーボード側の SnippetMenuLayout.maxRows と同じ値）
private let snippetMenuRows = 6

struct SnippetEditor: View {
    @State var snippet: Snippet
    let onSave: (Snippet) -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                TextEditor(text: $snippet.text)
                    .frame(minHeight: 160)
                    .focused($isFocused)
            }
            .navigationTitle("定型文")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(snippet)
                        dismiss()
                    }
                    .disabled(snippet.text.isEmpty)
                }
            }
            .onAppear { isFocused = true }
        }
    }
}

#Preview {
    NavigationStack {
        SnippetListView()
    }
}
