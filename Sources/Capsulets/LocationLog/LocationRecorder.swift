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
            case .detailed: "移動中は約 20 m おきに GPS で記録します。止まっている間の GPS の休止と、動き出したときの再開は iOS に任せます。バッテリー消費は大きめです。"
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
        stopLiveUpdates()
        guard mode != .off, authorization == .authorizedAlways || authorization == .authorizedWhenInUse else {
            return
        }
        manager.startMonitoringVisits()
        if mode != .visits {
            // 基地局が変わるくらい動いたときに届く。アプリが終了していても iOS が裏で起こしてくれる
            manager.startMonitoringSignificantLocationChanges()
        }
        if mode == .detailed {
            startLiveUpdates()
        }
    }

    // MARK: - 「通った道まで」（iOS 17 の CLLocationUpdate）

    /// これ以上動いたら記録する距離（m）
    private static let movementThreshold: CLLocationDistance = 20

    /// 裏でも位置を受け取り続けるためのセッション。持っている間だけ有効
    private var backgroundSession: CLBackgroundActivitySession?
    private var liveTask: Task<Void, Never>?
    /// 最後に記録した位置
    private var anchor: CLLocation?
    /// iOS が「止まっている」と判断して GPS を休ませているか（表示用）
    @Published private(set) var isStationary = false

    /// 位置の更新を受け取り始める。止まったら iOS が GPS を休ませ、動き出したら自動で再開する。
    /// 止まっているかの判断は iOS がモーションセンサーで行うので、アプリにモーションの許可は要らない
    private func startLiveUpdates() {
        backgroundSession = CLBackgroundActivitySession()
        liveTask = Task { [weak self] in
            do {
                for try await update in CLLocationUpdate.liveUpdates(.otherNavigation) {
                    guard let self, !Task.isCancelled else { return }
                    self.handleLiveUpdate(update)
                }
            } catch {
                // 受け取りが終わった。次に apply() が呼ばれたときに始め直す
            }
        }
    }

    private func stopLiveUpdates() {
        liveTask?.cancel()
        liveTask = nil
        backgroundSession?.invalidate()
        backgroundSession = nil
        isStationary = false
    }

    private func handleLiveUpdate(_ update: CLLocationUpdate) {
        if isStationary != update.isStationary {
            isStationary = update.isStationary
        }
        guard let location = update.location,
              location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 50
        else { return }
        // 前に記録した点から、誤差より大きく離れたときだけ記録する
        if let anchor, location.distance(from: anchor) < max(Self.movementThreshold, location.horizontalAccuracy) {
            return
        }
        anchor = location
        record(location)
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
            // 「通った道まで」の細かい点は CLLocationUpdate から受け取る。ここに届くのは大きな移動の通知
            for location in locations {
                record(location)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        MainActor.assumeIsolated {
            LocationStore.shared.add(visit)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // 一時的に位置が取れないだけのことが多いので、何もしない（次の通知を待つ）
    }
}
