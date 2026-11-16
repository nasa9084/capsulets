import Foundation

/// キーボードから入力できる定型文
struct Snippet: Codable, Identifiable, Equatable {
    var id = UUID()
    var text: String
}

/// 定型文の保存先（アプリで編集し、キーボード拡張機能が読む。App Group の UserDefaults）
enum SnippetStore {
    private static let storage = CapsuletStorage(prefix: "keyboard")
    private static let key = "snippets"

    static func load() -> [Snippet] { storage.decode([Snippet].self, key) ?? [] }
    static func save(_ snippets: [Snippet]) { storage.encode(snippets, key) }
}
