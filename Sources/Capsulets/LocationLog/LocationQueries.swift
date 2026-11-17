import CoreLocation
import Foundation

/// 期間の中の 1 行（滞在か移動）
struct TimelineRow: Identifiable {
    enum Kind {
        case stay
        case move
    }

    let id = UUID()
    let kind: Kind
    let start: Date
    /// 滞在中のときは nil
    let end: Date?
    let title: String
    let detail: String
    /// 滞在した場所（移動のときは nil）
    let coordinate: CLLocationCoordinate2D?
}

/// 期間で調べた結果
struct TimelineResult {
    var path: [CLLocationCoordinate2D] = []
    var rows: [TimelineRow] = []
    var pointCount = 0
}

@MainActor
enum LocationQueries {
    // MARK: - 期間から

    static func timeline(from start: Date, to end: Date) -> TimelineResult {
        let store = LocationStore.shared
        let points = store.points(from: start, to: end)
        let visits = store.visits(from: start, to: end)

        var result = TimelineResult()
        result.pointCount = points.count
        // 点が多いときは、地図に描く線を間引く
        let step = max(1, points.count / 3000)
        result.path = stride(from: 0, to: points.count, by: step).map { points[$0].coordinate }
        if let last = points.last, step > 1 {
            result.path.append(last.coordinate)
        }

        var cursor = start
        for visit in visits {
            if let move = moveRow(points, from: cursor, to: visit.arrival) {
                result.rows.append(move)
            }
            result.rows.append(TimelineRow(
                kind: .stay,
                start: visit.arrival,
                end: visit.departure,
                title: visit.placeName ?? "滞在",
                detail: visit.departure.map { durationText(from: visit.arrival, to: $0) } ?? "滞在中",
                coordinate: visit.coordinate
            ))
            cursor = max(cursor, visit.departure ?? end)
        }
        if let move = moveRow(points, from: cursor, to: end) {
            result.rows.append(move)
        }
        return result
    }

    private static func moveRow(_ points: [LocationPoint], from start: Date, to end: Date) -> TimelineRow? {
        guard start < end else { return nil }
        let segment = points.filter { $0.timestamp >= start && $0.timestamp <= end }
        guard segment.count >= 2, let first = segment.first, let last = segment.last else { return nil }
        var distance: CLLocationDistance = 0
        for (previous, next) in zip(segment, segment.dropFirst()) {
            distance += next.location.distance(from: previous.location)
        }
        // ほとんど動いていないものは、誤差の揺れなので出さない
        guard distance >= 100 else { return nil }
        return TimelineRow(
            kind: .move,
            start: first.timestamp,
            end: last.timestamp,
            title: "移動",
            detail: "約\(distanceText(distance))・\(durationText(from: first.timestamp, to: last.timestamp))",
            coordinate: nil
        )
    }

    /// 名前がまだない滞在の住所を調べて、覚えておく（1 回に調べる数は絞る）
    static func resolvePlaceNames(from start: Date, to end: Date, limit: Int = 8) async -> Bool {
        let store = LocationStore.shared
        let unnamed = store.visits(from: start, to: end).filter { $0.placeName == nil }.prefix(limit)
        guard !unnamed.isEmpty else { return false }
        let geocoder = CLGeocoder()
        var didResolve = false
        for visit in unnamed {
            guard let placemark = try? await geocoder.reverseGeocodeLocation(visit.location).first else { continue }
            let parts = [placemark.locality, placemark.subLocality, placemark.thoroughfare].compactMap { $0 }
            let address = parts.joined()
            if let name = placemark.name, !name.isEmpty, name != address, !address.contains(name) {
                visit.placeName = address.isEmpty ? name : "\(name)（\(address)）"
            } else if !address.isEmpty {
                visit.placeName = address
            } else {
                continue
            }
            didResolve = true
        }
        store.save()
        return didResolve
    }

    // MARK: - 場所から

    /// 中心から半径 radius（m）の中にいた時間帯。新しい順
    static func stays(near center: CLLocationCoordinate2D, radius: Double) -> [DateInterval] {
        let store = LocationStore.shared
        let centerLocation = CLLocation(latitude: center.latitude, longitude: center.longitude)
        let box = BoundingBox(center: center, radius: radius)
        var intervals: [DateInterval] = []

        for visit in store.visits(in: box) where visit.location.distance(from: centerLocation) <= radius {
            intervals.append(DateInterval(start: visit.arrival, end: max(visit.arrival, visit.departure ?? Date())))
        }

        // 範囲内の点を、時間が近いものどうしでまとめる
        let maxGap: TimeInterval = 20 * 60
        var current: DateInterval?
        for point in store.points(in: box) where point.location.distance(from: centerLocation) <= radius {
            if let interval = current, point.timestamp.timeIntervalSince(interval.end) <= maxGap {
                current = DateInterval(start: interval.start, end: max(interval.end, point.timestamp))
            } else {
                if let interval = current {
                    intervals.append(interval)
                }
                current = DateInterval(start: point.timestamp, duration: 0)
            }
        }
        if let interval = current {
            intervals.append(interval)
        }

        // 重なるもの・すぐ続くものを 1 つにする
        var merged: [DateInterval] = []
        for interval in intervals.sorted(by: { $0.start < $1.start }) {
            if let last = merged.last, interval.start.timeIntervalSince(last.end) <= 10 * 60 {
                merged[merged.count - 1] = DateInterval(start: last.start, end: max(last.end, interval.end))
            } else {
                merged.append(interval)
            }
        }
        return merged.reversed()
    }

    // MARK: - 表示用の文字

    static func durationText(from start: Date, to end: Date) -> String {
        let minutes = max(0, Int(end.timeIntervalSince(start) / 60))
        if minutes < 60 {
            return "\(minutes)分"
        }
        return minutes % 60 == 0 ? "\(minutes / 60)時間" : "\(minutes / 60)時間\(minutes % 60)分"
    }

    static func distanceText(_ meters: CLLocationDistance) -> String {
        meters < 1000 ? "\(Int(meters / 10) * 10) m" : String(format: "%.1f km", meters / 1000)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "H:mm"
        return formatter
    }()

    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "M/d(E) H:mm"
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy/M/d(E)"
        return formatter
    }()

    private static let preciseFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "M/d(E) H:mm:ss"
        return formatter
    }()

    static func preciseText(_ date: Date) -> String { preciseFormatter.string(from: date) }
    static func timeText(_ date: Date) -> String { timeFormatter.string(from: date) }
    static func dateTimeText(_ date: Date) -> String { dateTimeFormatter.string(from: date) }
    static func dateText(_ date: Date) -> String { dateFormatter.string(from: date) }

    /// 「9:12〜12:40」。日付をまたぐときは終わりにも日付を付ける
    static func rangeText(from start: Date, to end: Date?, showsDate: Bool) -> String {
        let startText = showsDate ? dateTimeText(start) : timeText(start)
        guard let end else { return "\(startText)〜" }
        let isSameDay = Calendar.current.isDate(start, inSameDayAs: end)
        return "\(startText)〜\(isSameDay ? timeText(end) : dateTimeText(end))"
    }
}
