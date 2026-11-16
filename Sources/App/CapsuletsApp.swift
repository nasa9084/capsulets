import SwiftUI

@main
struct CapsuletsApp: App {
    init() {
        // 位置の記録を再開する。iOS が位置の通知のために裏で起動したときも、ここを通る
        LocationRecorder.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

/// 画面下部のタブで capsulet を切り替える
struct RootView: View {
    /// 最後に開いていた capsulet を次回も開く
    @AppStorage("app.selectedCapsulet") private var selection = CapsuletRegistry.all.first?.id ?? ""
    /// データを読み込んだ capsulet の画面を作り直して、保存し直した内容を読ませるための目印
    @State private var reloadTokens: [String: UUID] = [:]
    @State private var pendingImport: PendingImport?
    @State private var importError: String?

    var body: some View {
        TabView(selection: $selection) {
            ForEach(CapsuletRegistry.all) { capsulet in
                capsulet.makeView()
                    .id(reloadTokens[capsulet.id])
                    .tabItem { Label(capsulet.title, systemImage: capsulet.systemImage) }
                    .tag(capsulet.id)
            }
        }
        .onOpenURL(perform: handle)
        .alert(
            "データを読み込みますか？",
            isPresented: Binding(get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } }),
            presenting: pendingImport
        ) { pending in
            Button("読み込む", role: .destructive) { apply(pending) }
            Button("キャンセル", role: .cancel) {}
        } message: { pending in
            Text("「\(pending.capsulet.title)」に\(pending.summary)を読み込みます。今のデータは置き換わります。")
        }
        .alert(
            "読み込めませんでした",
            isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })
        ) {
            Button("OK") {}
        } message: {
            Text(importError ?? "")
        }
    }

    /// `capsulets://import/<capsulet id>?data=<base64url の JSON>`
    private func handle(_ url: URL) {
        guard url.scheme == "capsulets", url.host() == "import" else { return }
        let id = url.lastPathComponent
        guard let capsulet = CapsuletRegistry.capsulet(id: id), let importer = capsulet.importer else {
            importError = "読み込み先（\(id)）が見つかりません。"
            return
        }
        guard
            let encoded = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "data" })?.value,
            let data = Data(base64URLEncoded: encoded)
        else {
            importError = "データが壊れています。"
            return
        }
        do {
            let summary = try importer.describe(data)
            selection = capsulet.id
            pendingImport = PendingImport(capsulet: capsulet, data: data, summary: summary)
        } catch {
            importError = "データの形式が違います。"
        }
    }

    private func apply(_ pending: PendingImport) {
        do {
            try pending.capsulet.importer?.apply(pending.data)
            reloadTokens[pending.capsulet.id] = UUID()
        } catch {
            importError = "保存に失敗しました。"
        }
    }
}

struct PendingImport {
    let capsulet: Capsulet
    let data: Data
    let summary: String
}

extension Data {
    /// URL に入れられる base64（`+` → `-`、`/` → `_`、`=` なし）を読む
    init?(base64URLEncoded string: String) {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        self.init(base64Encoded: base64)
    }
}

#Preview {
    RootView()
}
