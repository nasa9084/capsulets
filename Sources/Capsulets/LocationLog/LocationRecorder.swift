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
            case .detailed: "移動中は約 40 m おきに GPS で記録します。4 分ほど止まっていると GPS を休み、動き出すと再開します。バッテリー消費は大きめです。"
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
        tracking = .idle
        guard mode != .off, authorization == .authorizedAlways || authorization == .authorizedWhenInUse else {
            return
        }
        manager.startMonitoringVisits()
        if mode != .visits {
            // 基地局が変わるくらい動いたときに届く。アプリが終了していても iOS が裏で起こしてくれる
            manager.startMonitoringSignificantLocationChanges()
        }
        if mode == .detailed {
            manager.allowsBackgroundLocationUpdates = true
            manager.showsBackgroundLocationIndicator = false
            // iOS の自動の一時停止は、信号待ちなどで止まったあと再開が遅れ、道順が抜ける原因になる。
            // 止まっているかどうかは自分で判断して、GPS を使うかどうかを切り替える
            manager.pausesLocationUpdatesAutomatically = false
            manager.activityType = .other
            startPrecise()
            manager.startUpdatingLocation()
        }
    }

    // MARK: - 「通った道まで」の GPS の切り替え

    /// GPS で細かく追っている（precise）か、止まっているので粗い位置だけ見ている（resting）か
    private enum Tracking {
        case idle
        case precise
        case resting
    }

    /// これ以上動いたら「動いた」とみなす距離（m）
    private static let movementThreshold: CLLocationDistance = 40
    /// この時間動かなかったら、GPS を止めて休む
    private static let restAfter: TimeInterval = 4 * 60
    /// 休んでいる間に、ここから離れたら GPS を再開する距離（m）
    private static let wakeDistance: CLLocationDistance = 250

    private var tracking: Tracking = .idle
    /// 最後に「動いた」と判断した位置と時刻
    private var anchor: CLLocation?
    private var lastMovement = Date()

    private func startPrecise() {
        tracking = .precise
        lastMovement = Date()
        manager.desiredAccuracy = kCLLocationAccuracyBest
        // 位置は 1 秒ごとに受け取り、記録するかどうかはこちらで決める（止まっているかの判断に使う）
        manager.distanceFilter = kCLDistanceFilterNone
    }

    private func startResting() {
        tracking = .resting
        // GPS を使わない粗い位置（基地局・Wi-Fi）だけ受け取る。記録は止めずに続けるので、アプリは裏で動き続ける
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        manager.distanceFilter = Self.wakeDistance / 2
    }

    /// 「通った道まで」で位置が届いたとき
    private func handleDetailed(_ location: CLLocation) {
        switch tracking {
        case .idle:
            return
        case .precise:
            guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 65 else {
                // 誤差が大きい点は記録しないが、長く止まっているかどうかは見る
                if Date().timeIntervalSince(lastMovement) > Self.restAfter {
                    startResting()
                }
                return
            }
            if let anchor, location.distance(from: anchor) < Self.movementThreshold {
                if Date().timeIntervalSince(lastMovement) > Self.restAfter {
                    startResting()
                }
                return
            }
            anchor = location
            lastMovement = Date()
            record(location)
        case .resting:
            // 休む前の位置から離れていたら、動き出したので GPS を再開する
            guard let anchor else {
                startPrecise()
                return
            }
            if location.distance(from: anchor) > Self.wakeDistance + max(location.horizontalAccuracy, 0) / 2 {
                startPrecise()
            }
        }
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

    /// 滞在や大きな移動の通知が届いたら、休んでいても GPS を再開する
    private func resumeDetailedUpdatesIfPaused() {
        if mode == .detailed, tracking == .resting {
            startPrecise()
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
                if mode == .detailed {
                    handleDetailed(location)
                } else {
                    record(location)
                }
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        MainActor.assumeIsolated {
            LocationStore.shared.add(visit)
            resumeDetailedUpdatesIfPaused()
        }
    }

    nonisolated func locationManagerDidPauseLocationUpdates(_ manager: CLLocationManager) {
        // 自動の一時停止は切っているが、念のため止まったら再開する
        MainActor.assumeIsolated {
            if mode == .detailed {
                startPrecise()
                self.manager.startUpdatingLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // 一時的に位置が取れないだけのことが多いので、何もしない（次の通知を待つ）
    }
}
