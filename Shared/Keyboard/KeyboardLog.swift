import Foundation

/// キーボードの動きの記録。キーボード拡張機能が書き、アプリの「キーボードのログ」で読む。
/// App Group のファイルに置くので、キーボード側はフルアクセスがオンのときだけ書ける
enum KeyboardLog {
    struct Entry: Identifiable {
        let id = UUID()
        let line: String
    }

    private static let maxLines = 2000
    private static let queue = DispatchQueue(label: "com.nasa9084.capsulets.keyboard-log")
    private static let sessionKey = "keyboard.log.sessionOpen"

    private static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppGroup.id)?
            .appendingPathComponent("keyboard-log.txt")
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "MM/dd HH:mm:ss.SSS"
        return formatter
    }()

    /// 1 行書き足す。時刻とメモリ使用量を先頭に付ける
    static func add(_ message: String) {
        let line = "\(formatter.string(from: Date())) [\(memoryText())] \(message)"
        queue.async {
            guard let url = fileURL else { return }
            var lines = (try? String(contentsOf: url, encoding: .utf8))?
                .split(separator: "\n", omittingEmptySubsequences: true)
                .map(String.init) ?? []
            lines.append(line)
            if lines.count > maxLines {
                lines.removeFirst(lines.count - maxLines)
            }
            try? (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        }
    }

    /// キーボードを読み込んだときに呼ぶ。前回の終了の記録がなければ、強制終了された可能性を書き残す
    static func sessionStarted() {
        let defaults = AppGroup.defaults
        if defaults.bool(forKey: sessionKey) {
            add("⚠️ 前回のキーボードは終了の記録がない（メモリ不足などで iOS に強制終了された可能性）")
        }
        defaults.set(true, forKey: sessionKey)
    }

    static func sessionEnded() {
        AppGroup.defaults.set(false, forKey: sessionKey)
    }

    /// 新しい順
    static func load() -> [Entry] {
        guard let url = fileURL, let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").reversed().map { Entry(line: String($0)) }
    }

    static func text() -> String {
        guard let url = fileURL else { return "" }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    static func clear() {
        queue.sync {
            guard let url = fileURL else { return }
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// 今のメモリ使用量（MB）。キーボード拡張機能は数十 MB を超えると iOS に止められる
    static func memoryText() -> String {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return "?MB" }
        return String(format: "%.0fMB", Double(info.phys_footprint) / 1_048_576)
    }
}
