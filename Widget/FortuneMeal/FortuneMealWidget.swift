import AppIntents
import SwiftUI
import WidgetKit

// MARK: - くじを引く（ウィジェットのボタンから実行される）

struct FortuneMealDrawIntent: AppIntent {
    static var title: LocalizedStringResource = "くじを引く"
    static var isDiscoverable = false

    @Parameter(title: "プリセット")
    var presetID: String

    init() {}

    init(presetID: String) {
        self.presetID = presetID
    }

    func perform() async throws -> some IntentResult {
        let meals = FortuneMealStore.loadMeals() ?? []
        let candidates: [Meal]
        let source: String

        if let preset = FortuneMealStore.loadPresets()?.first(where: { $0.id.uuidString == presetID }) {
            candidates = meals.filter { preset.mealIDs.contains($0.id) }
            source = preset.name
        } else {
            return .result()
        }

        if let pick = candidates.randomElement() {
            FortuneMealStore.setLastResult(pick.name, source: source)
        }
        return .result()
    }
}

// MARK: - タイムライン

struct FortuneMealDrawButton: Hashable {
    let id: String
    let title: String
}

struct FortuneMealEntry: TimelineEntry {
    let date: Date
    let result: String?
    let source: String?
    let buttons: [FortuneMealDrawButton]
}

struct FortuneMealProvider: TimelineProvider {
    func placeholder(in context: Context) -> FortuneMealEntry {
        FortuneMealEntry(
            date: .now,
            result: "カレー",
            source: "こってり",
            buttons: [
                FortuneMealDrawButton(id: "a", title: "こってり"),
                FortuneMealDrawButton(id: "b", title: "さっぱり"),
            ]
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (FortuneMealEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FortuneMealEntry>) -> Void) {
        // 内容が変わるのはボタンを押したときかアプリで編集したときだけなので、自動更新はしない
        completion(Timeline(entries: [currentEntry()], policy: .never))
    }

    private func currentEntry() -> FortuneMealEntry {
        let presets = FortuneMealStore.loadPresets() ?? []
        return FortuneMealEntry(
            date: .now,
            result: FortuneMealStore.lastResult,
            source: FortuneMealStore.lastSource,
            buttons: presets.map { FortuneMealDrawButton(id: $0.id.uuidString, title: $0.name) }
        )
    }
}

// MARK: - 見た目

struct FortuneMealWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: FortuneMealEntry

    private var isSmall: Bool { family == .systemSmall }

    /// サイズごとのボタンの最大数と列数
    private var layout: (max: Int, columns: Int) {
        switch family {
        case .systemSmall: (4, 2)
        case .systemMedium: (6, 3)
        default: (12, 3)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isSmall ? 4 : 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text(entry.source.map { "\($0)から" } ?? "今日のごはんは")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(entry.result ?? "？")
                    .font(isSmall ? .headline : .title2.bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }

            Spacer(minLength: 0)

            if entry.buttons.isEmpty {
                Text("アプリでプリセットを作ってください")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: layout.columns),
                    spacing: 4
                ) {
                    ForEach(Array(entry.buttons.prefix(layout.max)), id: \.self) { button in
                        Button(intent: FortuneMealDrawIntent(presetID: button.id)) {
                            Text(button.title)
                                .font(.caption2.bold())
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(.orange)
                    }
                }
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct FortuneMealWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: FortuneMealWidgetKind.kind, provider: FortuneMealProvider()) { entry in
            FortuneMealWidgetView(entry: entry)
        }
        .configurationDisplayName("ごはんくじ")
        .description("プリセットを選んでくじを引けます")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
