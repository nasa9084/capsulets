import Foundation

/// キーボードの設定（アプリで変えて、キーボード拡張機能が読む。App Group の UserDefaults）
enum KeyboardSettings {
    private static let storage = CapsuletStorage(prefix: "keyboard")
    private static let deleteFlickDistanceKey = "deleteFlickDistance"

    /// 削除キーの行削除フリックと判定する指の移動距離（pt）の選択肢
    static let deleteFlickDistanceChoices: [(title: String, distance: Double)] = [
        ("敏感", 16),
        ("ふつう", 32),
        ("鈍め", 48),
        ("かなり鈍め", 64),
    ]
    static let defaultDeleteFlickDistance: Double = 32

    static var deleteFlickDistance: Double {
        get {
            let value = storage.defaults.double(forKey: storage.key(deleteFlickDistanceKey))
            return value > 0 ? value : defaultDeleteFlickDistance
        }
        set {
            storage.defaults.set(newValue, forKey: storage.key(deleteFlickDistanceKey))
        }
    }
}
