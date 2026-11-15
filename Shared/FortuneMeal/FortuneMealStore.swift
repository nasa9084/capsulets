import Foundation

struct Meal: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var isSelected: Bool = true
    /// Google Maps の共有リンク、または住所・店名
    var place: String?
    var memo: String?
}

extension Meal {
    private var trimmedPlace: String? {
        guard let place = place?.trimmingCharacters(in: .whitespacesAndNewlines), !place.isEmpty else { return nil }
        return place
    }

    /// place がリンクならそのまま開く（お店のページ）。住所・店名なら Google Maps の経路案内を開く
    var placeIsLink: Bool {
        guard let place = trimmedPlace, let url = URL(string: place) else { return false }
        return url.scheme == "https" || url.scheme == "http"
    }

    var mapsURL: URL? {
        guard let place = trimmedPlace else { return nil }
        if placeIsLink { return URL(string: place) }
        var components = URLComponents(string: "https://www.google.com/maps/dir/")!
        components.queryItems = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "destination", value: place),
        ]
        return components.url
    }
}

/// 候補の選び方を名前を付けて保存したもの（「こってり」「さっぱり」など）
struct Preset: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var mealIDs: Set<UUID>
}

/// ごはんくじのデータ（アプリとウィジェットで共有する App Group の UserDefaults に保存する）
enum FortuneMealStore {
    private static let storage = CapsuletStorage(prefix: "fortuneMeal")

    private enum Key {
        static let meals = "meals"
        static let presets = "presets"
        static let lastResult = "lastResult"
        static let lastSource = "lastSource"
    }

    static func loadMeals() -> [Meal]? { storage.decode([Meal].self, Key.meals) }
    static func saveMeals(_ meals: [Meal]) { storage.encode(meals, Key.meals) }

    static func loadPresets() -> [Preset]? { storage.decode([Preset].self, Key.presets) }
    static func savePresets(_ presets: [Preset]) { storage.encode(presets, Key.presets) }

    static var lastResult: String? { storage.string(Key.lastResult) }
    static var lastSource: String? { storage.string(Key.lastSource) }

    static func setLastResult(_ result: String, source: String) {
        storage.set(result, Key.lastResult)
        storage.set(source, Key.lastSource)
    }
}
