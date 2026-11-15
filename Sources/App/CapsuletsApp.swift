import SwiftUI

@main
struct CapsuletsApp: App {
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

    var body: some View {
        TabView(selection: $selection) {
            ForEach(CapsuletRegistry.all) { capsulet in
                capsulet.makeView()
                    .tabItem { Label(capsulet.title, systemImage: capsulet.systemImage) }
                    .tag(capsulet.id)
            }
        }
    }
}

#Preview {
    RootView()
}
