import Foundation
import SwiftUI

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

    // MARK: - 色

    private static let accentColorKey = "accentColor"

    /// フリックの表示・候補の選択・確定キーに使う色の選択肢。値は 16 進の RGB
    static let accentColorChoices: [(title: String, hex: String)] = [
        ("青", "3478F6"),
        ("水色", "32ADE6"),
        ("緑", "34C759"),
        ("オレンジ", "FF9500"),
        ("赤", "FF3B30"),
        ("ピンク", "FF2D55"),
        ("紫", "AF52DE"),
        ("グレー", "8E8E93"),
    ]
    static let defaultAccentColor = "3478F6"

    static var accentColor: String {
        get { storage.string(accentColorKey) ?? defaultAccentColor }
        set { storage.set(newValue, accentColorKey) }
    }

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

extension Color {
    /// 16 進の RGB（"3478F6"）から作る
    init(hex: String) {
        let value = UInt32(hex, radix: 16) ?? 0x3478F6
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
