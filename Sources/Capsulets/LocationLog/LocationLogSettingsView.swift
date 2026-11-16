import CoreLocation
import SwiftUI

/// 記録の細かさ、位置情報の許可、たまった記録の件数と削除
struct LocationLogSettingsView: View {
    @ObservedObject private var recorder = LocationRecorder.shared
    @Environment(\.dismiss) private var dismiss

    @State private var pointCount = 0
    @State private var visitCount = 0
    @State private var oldestDate: Date?
    @State private var isConfirmingDeleteOld = false
    @State private var isConfirmingDeleteAll = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("記録の細かさ", selection: $recorder.mode) {
                        ForEach(LocationRecorder.Mode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("記録の細かさ")
                } footer: {
                    Text(recorder.mode.detail)
                }

                Section {
                    LabeledContent("位置情報の許可", value: authorizationText)
                    if recorder.authorization == .notDetermined || recorder.authorization == .authorizedWhenInUse {
                        Button("許可を求める") {
                            recorder.requestAuthorizationIfNeeded()
                        }
                    }
                    Button("iOS の設定を開く") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                } footer: {
                    Text("アプリを閉じている間も記録するには、位置情報を「常に」許可する必要があります。「使用中のみ」では、アプリを開いている間しか記録されません。")
                }

                Section("記録") {
                    LabeledContent("記録した点", value: "\(pointCount)件")
                    LabeledContent("滞在", value: "\(visitCount)件")
                    if let oldestDate {
                        LabeledContent("いちばん古い記録", value: LocationQueries.dateText(oldestDate))
                    }
                }

                Section {
                    Button("1年より前の記録を削除", role: .destructive) {
                        isConfirmingDeleteOld = true
                    }
                    Button("すべての記録を削除", role: .destructive) {
                        isConfirmingDeleteAll = true
                    }
                } footer: {
                    Text("記録はこの iPhone の中だけに保存しています。")
                }
            }
            .navigationTitle("足あとの設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { dismiss() }
                }
            }
            .confirmationDialog("1年より前の記録を削除しますか？", isPresented: $isConfirmingDeleteOld, titleVisibility: .visible) {
                Button("削除", role: .destructive) {
                    let cutoff = Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date()
                    LocationStore.shared.delete(before: cutoff)
                    reloadCounts()
                }
            } message: {
                Text("元に戻せません。")
            }
            .confirmationDialog("すべての記録を削除しますか？", isPresented: $isConfirmingDeleteAll, titleVisibility: .visible) {
                Button("すべて削除", role: .destructive) {
                    LocationStore.shared.deleteAll()
                    reloadCounts()
                }
            } message: {
                Text("元に戻せません。")
            }
            .onAppear(perform: reloadCounts)
        }
    }

    private var authorizationText: String {
        switch recorder.authorization {
        case .authorizedAlways: "常に"
        case .authorizedWhenInUse: "使用中のみ"
        case .denied: "許可しない"
        case .restricted: "制限あり"
        case .notDetermined: "未設定"
        @unknown default: "不明"
        }
    }

    private func reloadCounts() {
        let store = LocationStore.shared
        pointCount = store.pointCount
        visitCount = store.visitCount
        oldestDate = store.oldestDate
    }
}
