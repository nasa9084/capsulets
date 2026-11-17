import CoreLocation
import Foundation
import SwiftData
import UIKit

/// 記録した 1 点
@Model
final class LocationPoint {
    var timestamp: Date
    var latitude: Double
    var longitude: Double
    /// 水平方向の誤差（m）
    var accuracy: Double
    /// アプリを開いていない間（裏で動いているか、iOS に起こされたとき）に記録したか
    var recordedInBackground: Bool = false

    init(timestamp: Date, latitude: Double, longitude: Double, accuracy: Double, recordedInBackground: Bool) {
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.accuracy = accuracy
        self.recordedInBackground = recordedInBackground
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var location: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }
}

/// iOS が検出した滞在（ある場所に着いてから離れるまで）
@Model
final class StayVisit {
    var arrival: Date
    /// まだ滞在中のときは nil
    var departure: Date?
    var latitude: Double
    var longitude: Double
    var accuracy: Double
    /// 住所から付けた場所の名前（表示するときに調べて覚えておく）
    var placeName: String?

    init(arrival: Date, departure: Date?, latitude: Double, longitude: Double, accuracy: Double) {
        self.arrival = arrival
        self.departure = departure
        self.latitude = latitude
        self.longitude = longitude
        self.accuracy = accuracy
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var location: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }
}

/// 位置の記録の保存先（端末の中だけに置く）
@MainActor
final class LocationStore {
    static let shared = LocationStore()

    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }
    private var lastPointDate: Date?

    private init() {
        do {
            container = try ModelContainer(for: LocationPoint.self, StayVisit.self)
        } catch {
            // 保存先を開けないときも、アプリ全体は落とさない（この起動の間だけメモリに置く）
            let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
            // swiftlint:disable:next force_try
            container = try! ModelContainer(for: LocationPoint.self, StayVisit.self, configurations: configuration)
        }
    }

    // MARK: - 記録

    func add(_ location: CLLocation) {
        // 同じ場所の通知が続けて届くことがあるので、数秒以内のものは捨てる。
        // アプリを起動し直した直後は、iOS が前回と同じ位置をもう一度届けるので、保存済みの最後の点とも比べる
        if lastPointDate == nil {
            lastPointDate = recentPoints(limit: 1).first?.timestamp
        }
        if let lastPointDate, abs(location.timestamp.timeIntervalSince(lastPointDate)) < 5 {
            return
        }
        lastPointDate = location.timestamp
        context.insert(LocationPoint(
            timestamp: location.timestamp,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            accuracy: location.horizontalAccuracy,
            recordedInBackground: UIApplication.shared.applicationState != .active
        ))
        try? context.save()
    }

    /// 滞在は「着いた」ときと「離れた」ときの 2 回届く。2 回目は 1 回目の記録を更新する
    func add(_ visit: CLVisit) {
        let arrival = visit.arrivalDate == .distantPast ? Date() : visit.arrivalDate
        let departure: Date? = visit.departureDate == .distantFuture ? nil : visit.departureDate
        var descriptor = FetchDescriptor<StayVisit>(predicate: #Predicate<StayVisit> { $0.arrival == arrival })
        descriptor.fetchLimit = 1
        if let existing = try? context.fetch(descriptor).first {
            existing.departure = departure
        } else {
            context.insert(StayVisit(
                arrival: arrival,
                departure: departure,
                latitude: visit.coordinate.latitude,
                longitude: visit.coordinate.longitude,
                accuracy: visit.horizontalAccuracy
            ))
        }
        try? context.save()
    }

    func save() {
        try? context.save()
    }

    // MARK: - 検索

    func points(from start: Date, to end: Date) -> [LocationPoint] {
        let descriptor = FetchDescriptor<LocationPoint>(
            predicate: #Predicate<LocationPoint> { $0.timestamp >= start && $0.timestamp <= end },
            sortBy: [SortDescriptor(\.timestamp)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// 期間に少しでも重なる滞在
    func visits(from start: Date, to end: Date) -> [StayVisit] {
        let descriptor = FetchDescriptor<StayVisit>(
            predicate: #Predicate<StayVisit> { $0.arrival <= end },
            sortBy: [SortDescriptor(\.arrival)]
        )
        let visits = (try? context.fetch(descriptor)) ?? []
        return visits.filter { ($0.departure ?? .distantFuture) >= start }
    }

    func points(in box: BoundingBox) -> [LocationPoint] {
        let (minLat, maxLat, minLon, maxLon) = (box.minLatitude, box.maxLatitude, box.minLongitude, box.maxLongitude)
        let descriptor = FetchDescriptor<LocationPoint>(
            predicate: #Predicate<LocationPoint> {
                $0.latitude >= minLat && $0.latitude <= maxLat && $0.longitude >= minLon && $0.longitude <= maxLon
            },
            sortBy: [SortDescriptor(\.timestamp)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func visits(in box: BoundingBox) -> [StayVisit] {
        let (minLat, maxLat, minLon, maxLon) = (box.minLatitude, box.maxLatitude, box.minLongitude, box.maxLongitude)
        let descriptor = FetchDescriptor<StayVisit>(
            predicate: #Predicate<StayVisit> {
                $0.latitude >= minLat && $0.latitude <= maxLat && $0.longitude >= minLon && $0.longitude <= maxLon
            },
            sortBy: [SortDescriptor(\.arrival)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// 新しい順に limit 件
    func recentPoints(limit: Int) -> [LocationPoint] {
        var descriptor = FetchDescriptor<LocationPoint>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        descriptor.fetchLimit = limit
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - 件数と削除

    var pointCount: Int {
        (try? context.fetchCount(FetchDescriptor<LocationPoint>())) ?? 0
    }

    var visitCount: Int {
        (try? context.fetchCount(FetchDescriptor<StayVisit>())) ?? 0
    }

    var oldestDate: Date? {
        var descriptor = FetchDescriptor<LocationPoint>(sortBy: [SortDescriptor(\.timestamp)])
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first?.timestamp
    }

    func deleteAll() {
        try? context.delete(model: LocationPoint.self)
        try? context.delete(model: StayVisit.self)
        try? context.save()
    }

    func delete(before date: Date) {
        try? context.delete(model: LocationPoint.self, where: #Predicate<LocationPoint> { $0.timestamp < date })
        try? context.delete(model: StayVisit.self, where: #Predicate<StayVisit> { $0.arrival < date })
        try? context.save()
    }
}

/// 緯度経度の四角い範囲（まず四角で絞り込んでから、距離を正確に測る）
struct BoundingBox {
    let minLatitude: Double
    let maxLatitude: Double
    let minLongitude: Double
    let maxLongitude: Double

    /// 中心から半径 radius（m）の円がすっぽり入る四角
    init(center: CLLocationCoordinate2D, radius: Double) {
        let latitudeDelta = radius / 111_000
        let longitudeDelta = radius / (111_000 * max(cos(center.latitude * .pi / 180), 0.01))
        minLatitude = center.latitude - latitudeDelta
        maxLatitude = center.latitude + latitudeDelta
        minLongitude = center.longitude - longitudeDelta
        maxLongitude = center.longitude + longitudeDelta
    }
}
