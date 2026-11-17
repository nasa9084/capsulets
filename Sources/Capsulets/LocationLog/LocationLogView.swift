import MapKit
import SwiftUI

/// 位置の記録を、時間から・地図から調べる
struct LocationLogView: View {
    enum Tab: String, CaseIterable {
        case time = "時間から"
        case place = "地図から"
    }

    @State private var tab: Tab = .time
    @State private var start = Calendar.current.startOfDay(for: Date())
    @State private var end = Date()
    @State private var showsSettings = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("調べ方", selection: $tab) {
                    ForEach(Tab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)

                switch tab {
                case .time:
                    TimelineSearchView(start: $start, end: $end)
                case .place:
                    PlaceSearchView { interval in
                        // その時間帯の前後 30 分を、時間からの画面で開く
                        start = interval.start.addingTimeInterval(-30 * 60)
                        end = interval.end.addingTimeInterval(30 * 60)
                        tab = .time
                    }
                }
            }
            .navigationTitle("足あと")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("設定", systemImage: "gearshape") {
                        showsSettings = true
                    }
                }
            }
            .sheet(isPresented: $showsSettings) {
                LocationLogSettingsView()
            }
        }
    }
}

// MARK: - 時間から

/// 期間を選ぶと、その間の移動を地図に、滞在と移動を一覧に出す
struct TimelineSearchView: View {
    @Binding var start: Date
    @Binding var end: Date

    @State private var result = TimelineResult()
    @State private var position: MapCameraPosition = .automatic

    private var spansMultipleDays: Bool {
        !Calendar.current.isDate(start, inSameDayAs: end)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                DatePicker("開始", selection: $start)
                DatePicker("終了", selection: $end)
                HStack {
                    Menu("期間を選ぶ") {
                        Button("今日") { setDay(offset: 0) }
                        Button("昨日") { setDay(offset: -1) }
                        Button("過去7日間") {
                            end = Date()
                            start = Calendar.current.startOfDay(for: end.addingTimeInterval(-6 * 24 * 60 * 60))
                        }
                    }
                    Spacer()
                    Text("\(result.pointCount)点")
                        .foregroundStyle(.secondary)
                }
                .font(.footnote)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)

            Map(position: $position) {
                if result.path.count >= 2 {
                    MapPolyline(coordinates: result.path)
                        .stroke(.blue, lineWidth: 3)
                }
                ForEach(result.rows) { row in
                    if let coordinate = row.coordinate {
                        Marker(row.title, coordinate: coordinate)
                    }
                }
                UserAnnotation()
            }
            .frame(height: 260)

            List {
                if result.rows.isEmpty {
                    Text("この期間の記録はありません")
                        .foregroundStyle(.secondary)
                }
                ForEach(result.rows) { row in
                    Button {
                        if let coordinate = row.coordinate {
                            position = .region(MKCoordinateRegion(
                                center: coordinate, latitudinalMeters: 600, longitudinalMeters: 600
                            ))
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: row.kind == .stay ? "mappin.circle.fill" : "figure.walk")
                                .foregroundStyle(row.kind == .stay ? Color.red : Color.blue)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.title)
                                    .foregroundStyle(Color.primary)
                                Text("\(LocationQueries.rangeText(from: row.start, to: row.end, showsDate: spansMultipleDays))　\(row.detail)")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
        .onAppear(perform: reload)
        .onChange(of: start) { _, _ in reload() }
        .onChange(of: end) { _, _ in reload() }
    }

    private func setDay(offset: Int) {
        let calendar = Calendar.current
        let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: Date())) ?? Date()
        start = day
        end = offset == 0 ? Date() : (calendar.date(byAdding: .day, value: 1, to: day) ?? Date()).addingTimeInterval(-1)
    }

    private func reload() {
        let (start, end) = (start, end)
        result = LocationQueries.timeline(from: start, to: end)
        position = .automatic
        // 滞在した場所の名前は、あとから調べて付ける
        Task {
            if await LocationQueries.resolvePlaceNames(from: start, to: end), start == self.start, end == self.end {
                result = LocationQueries.timeline(from: start, to: end)
            }
        }
    }
}

// MARK: - 地図から

/// 地図の中心の近くにいた時間帯を探す
struct PlaceSearchView: View {
    let onSelect: (DateInterval) -> Void

    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var center: CLLocationCoordinate2D?
    @State private var radius: Double = 200
    /// nil はまだ探していない
    @State private var results: [DateInterval]?

    /// 地図の縦 1 pt が何 m か（範囲の円の大きさを決めるのに使う）
    @State private var metersPerPoint: Double?

    private static let radiusChoices: [Double] = [100, 200, 500, 1000]
    private static let mapHeight: CGFloat = 300

    var body: some View {
        VStack(spacing: 0) {
            // 探す範囲の円は、地図の中身としてではなく上に重ねて描く。
            // 地図の中身に入れると「円が動く → 地図が円に合わせて動く → 中心が変わる → 円が動く」と
            // 繰り返して固まる
            Map(position: $position) {
                UserAnnotation()
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                center = context.region.center
                metersPerPoint = context.region.span.latitudeDelta * 111_000 / Self.mapHeight
            }
            .overlay {
                ZStack {
                    if let metersPerPoint, metersPerPoint > 0 {
                        let diameter = min(radius * 2 / metersPerPoint, 4000)
                        Circle()
                            .fill(.blue.opacity(0.15))
                            .overlay(Circle().stroke(.blue, lineWidth: 1))
                            .frame(width: diameter, height: diameter)
                    }
                    // 地図の中心（ここを基準に探す）
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.blue)
                }
                .allowsHitTesting(false)
            }
            .frame(height: Self.mapHeight)
            .clipped()

            VStack(spacing: 8) {
                Picker("範囲", selection: $radius) {
                    ForEach(Self.radiusChoices, id: \.self) { radius in
                        Text(LocationQueries.distanceText(radius)).tag(radius)
                    }
                }
                .pickerStyle(.segmented)
                Button("この場所にいた日時を探す", systemImage: "magnifyingglass") {
                    if let center {
                        results = LocationQueries.stays(near: center, radius: radius)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(center == nil)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            List {
                if let results {
                    if results.isEmpty {
                        Text("この場所の記録はありません")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(results, id: \.self) { interval in
                        Button {
                            onSelect(interval)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(LocationQueries.dateText(interval.start))
                                    .foregroundStyle(Color.primary)
                                Text(detail(interval))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } else {
                    Text("地図を動かして、調べたい場所を中心の＋に合わせてください")
                        .foregroundStyle(.secondary)
                }
            }
            .listStyle(.plain)
        }
    }

    private func detail(_ interval: DateInterval) -> String {
        // 1 点だけのときは、通りかかっただけ
        if interval.duration < 60 {
            return "\(LocationQueries.timeText(interval.start)) ごろ通過"
        }
        let range = LocationQueries.rangeText(from: interval.start, to: interval.end, showsDate: false)
        return "\(range)　\(LocationQueries.durationText(from: interval.start, to: interval.end))"
    }
}

#Preview {
    LocationLogView()
}
