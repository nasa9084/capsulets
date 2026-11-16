/// 絵文字を名前（:thinking_face: の中身）で探す
enum EmojiNames {
    struct Entry {
        let name: String
        let emoji: String
    }

    /// 最初に使うときに表を読み込む
    private static let entries: [Entry] = EmojiNameData.table.split(separator: "\n").compactMap { line in
        let parts = line.split(separator: " ")
        return parts.count == 2 ? Entry(name: String(parts[0]), emoji: String(parts[1])) : nil
    }

    private static let byName = Dictionary(entries.map { ($0.name, $0.emoji) }) { first, _ in first }

    /// 名前がぴったり一致する絵文字
    static func emoji(named name: String) -> String? {
        byName[name]
    }

    /// 名前が query で始まるものを先に、途中に含むものをそのあとに並べる。同じ絵文字は 1 回だけ出す
    static func search(_ query: String, limit: Int) -> [Entry] {
        var seen = Set<String>()
        var prefixMatches: [Entry] = []
        var otherMatches: [Entry] = []
        for entry in entries where entry.name.contains(query) {
            if entry.name.hasPrefix(query) {
                prefixMatches.append(entry)
            } else {
                otherMatches.append(entry)
            }
        }
        // 短い名前ほど、打った文字に近い
        prefixMatches.sort { $0.name.count < $1.name.count }
        return (prefixMatches + otherMatches).filter { seen.insert($0.emoji).inserted }.prefix(limit).map { $0 }
    }
}
