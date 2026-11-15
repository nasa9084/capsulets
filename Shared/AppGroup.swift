import Foundation

/// アプリ本体とウィジェットで共有する保存先（すべての capsulet で1つの App Group を使う）
enum AppGroup {
    static let baseBundleID = "com.nasa9084.capsulets"
    static let widgetBundleSuffix = ".Widgets"

    /// SideStore は Bundle ID と App Group ID の末尾に Team ID を付けて署名し直す。
    /// （例: com.nasa9084.capsulets.ABCDE12345 / group.com.nasa9084.capsulets.ABCDE12345）
    /// 実行中の Bundle ID から App Group ID を組み立てれば、どちらの環境でも一致する。
    static var id: String {
        var id = Bundle.main.bundleIdentifier ?? baseBundleID
        if id.hasSuffix(widgetBundleSuffix) {
            id.removeLast(widgetBundleSuffix.count)
        }
        return "group." + id
    }

    static var defaults: UserDefaults {
        UserDefaults(suiteName: id) ?? .standard
    }
}

/// capsulet ごとにキーの接頭辞を付けて、同じ UserDefaults の中で名前がぶつからないようにする
struct CapsuletStorage {
    let prefix: String

    var defaults: UserDefaults { AppGroup.defaults }

    func key(_ name: String) -> String { "\(prefix).\(name)" }

    func string(_ name: String) -> String? { defaults.string(forKey: key(name)) }
    func set(_ value: String?, _ name: String) { defaults.set(value, forKey: key(name)) }

    func decode<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        guard let data = defaults.data(forKey: key(name)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    func encode<T: Encodable>(_ value: T, _ name: String) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key(name))
        }
    }
}
