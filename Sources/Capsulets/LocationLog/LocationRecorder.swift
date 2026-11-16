import CoreLocation
import SwiftUI

/// 位置をバックグラウンドで記録する。アプリの起動時（iOS に裏で起こされたときも含む）に start() を呼ぶ
@MainActor
final class LocationRecorder: NSObject, ObservableObject {
    static let shared = LocationRecorder()

    /// 記録の細かさ。下に行くほど細かく、バッテリーを使う
    enum Mode: String, CaseIterable, Identifiable {
        case off
        case visits
        case coarse
        case detailed

        var id: String { rawValue }

        var title: String {
            switch self {
            case .off: "記録しない"
            case .visits: "滞在だけ"
            case .coarse: "滞在＋移動のあらまし"
            case .detailed: "通った道まで"
            }
        }

        var detail: String {
            switch self {
            case .off: "位置を記録しません。"
            case .visits: "どこに、いつからいつまでいたかだけを記録します。バッテリー消費は最小です。"
            case .coarse: "滞在に加えて、移動中は数百 m〜数 km おきに記録します。バッテリー消費はごく小さいです。"
            case .detailed: "移動中は約 50 m おきに GPS で記録します。止まっている間は自動で休みます。バッテリー消費は中くらいです。"
            }
        }
    }

    @Published private(set) var authorization: CLAuthorizationStatus = .notDetermined
    @Published var mode: Mode {
        didSet {
            storage.set(mode.rawValue, Self.modeKey)
            if mode != .off {
                requestAuthorizationIfNeeded()
            }
            apply()
        }
    }

    private static let modeKey = "mode"
    private let storage = CapsuletStorage(prefix: "locationLog")
    private let manager = CLLocationManager()
    /// 「通った道まで」で、止まっていて iOS が記録を休ませている間 true
    private var isPaused = false

    override private init() {
        mode = Mode(rawValue: CapsuletStorage(prefix: "locationLog").string(Self.modeKey) ?? "") ?? .off
        super.init()
        manager.delegate = self
        authorization = manager.authorizationStatus
    }

    func start() {
        apply()
    }

    /// 今の設定と許可に合わせて、記録を始め直す
    private func apply() {
        manager.stopMonitoringVisits()
        manager.stopMonitoringSignificantLocationChanges()
        manager.stopUpdatingLocation()
        isPaused = false
        guard mode != .off, authorization == .authorizedAlways || authorization == .authorizedWhenInUse else {
            return
        }
        manager.startMonitoringVisits()
        if mode != .visits {
            // 基地局が変わるくらい動いたときに届く。アプリが終了していても iOS が裏で起こしてくれる
            manager.startMonitoringSignificantLocationChanges()
        }
        if mode == .detailed {
            startDetailedUpdates()
        }
    }

    private func startDetailedUpdates() {
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 50
        manager.activityType = .other
        // 止まっている間は iOS に休ませてもらう。動き出したら、滞在や大きな移動の通知をきっかけに再開する
        manager.pausesLocationUpdatesAutomatically = true
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = false
        manager.startUpdatingLocation()
    }

    /// 許可を 1 段ずつ求める（使用中のみ → 常に）
    func requestAuthorizationIfNeeded() {
        switch authorization {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            manager.requestAlwaysAuthorization()
        default:
            break
        }
    }

    private func record(_ location: CLLocation) {
        // 誤差が大きすぎる点と、古すぎる点は捨てる
        let maxAccuracy: Double = mode == .detailed ? 100 : 3000
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= maxAccuracy,
              abs(location.timestamp.timeIntervalSinceNow) < 24 * 60 * 60
        else { return }
        LocationStore.shared.add(location)
    }

    private func resumeDetailedUpdatesIfPaused() {
        if mode == .detailed, isPaused {
            isPaused = false
            manager.startUpdatingLocation()
        }
    }
}

extension LocationRecorder: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        MainActor.assumeIsolated {
            let previous = authorization
            authorization = status
            // 「使用中のみ」をもらえたら、続けて「常に」を求める
            if status == .authorizedWhenInUse, previous == .notDetermined, mode != .off {
                self.manager.requestAlwaysAuthorization()
            }
            apply()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        MainActor.assumeIsolated {
            for location in locations {
                record(location)
            }
            resumeDetailedUpdatesIfPaused()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        MainActor.assumeIsolated {
            LocationStore.shared.add(visit)
            resumeDetailedUpdatesIfPaused()
        }
    }

    nonisolated func locationManagerDidPauseLocationUpdates(_ manager: CLLocationManager) {
        MainActor.assumeIsolated {
            isPaused = true
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // 一時的に位置が取れないだけのことが多いので、何もしない（次の通知を待つ）
    }
}
