import SwiftUI

/// 1つのサブアプリ。タブに出す名前とアイコン、中身の画面を持つ
struct Capsulet: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    /// `capsulets://import/<id>?data=...` で外からデータを読み込めるようにするなら指定する
    let importer: CapsuletImporter?
    let makeView: @MainActor () -> AnyView

    init<Content: View>(
        id: String,
        title: String,
        systemImage: String,
        importer: CapsuletImporter? = nil,
        @ViewBuilder content: @escaping @MainActor () -> Content
    ) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.importer = importer
        self.makeView = { AnyView(content()) }
    }
}

/// 外から渡されたデータの読み込み方
struct CapsuletImporter {
    /// 読み込む前の確認ダイアログに出す説明（「候補12件、プリセット3件」など）。読めないデータなら throw する
    let describe: (Data) throws -> String
    /// 実際に保存する
    let apply: (Data) throws -> Void
}

/// タブに並べる capsulet の一覧。新しいサブアプリはここに足す
enum CapsuletRegistry {
    static let all: [Capsulet] = [
        Capsulet(
            id: "fortuneMeal",
            title: "ごはんくじ",
            systemImage: "fork.knife",
            importer: CapsuletImporter(
                describe: { data in
                    let export = try FortuneMealStore.decodeExport(data)
                    return "候補\(export.meals.count)件、プリセット\(export.presets.count)件"
                },
                apply: { data in
                    FortuneMealStore.applyExport(try FortuneMealStore.decodeExport(data))
                }
            )
        ) {
            FortuneMealView()
        },
        Capsulet(id: "keyboard", title: "キーボード", systemImage: "keyboard") {
            KeyboardGuideView()
        },
        Capsulet(id: "locationLog", title: "足あと", systemImage: "point.topleft.down.to.point.bottomright.curvepath") {
            LocationLogView()
        },
    ]

    static func capsulet(id: String) -> Capsulet? {
        all.first { $0.id == id }
    }
}
