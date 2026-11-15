import SwiftUI

/// 1つのサブアプリ。タブに出す名前とアイコン、中身の画面を持つ
struct Capsulet: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let makeView: @MainActor () -> AnyView

    init<Content: View>(
        id: String,
        title: String,
        systemImage: String,
        @ViewBuilder content: @escaping @MainActor () -> Content
    ) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.makeView = { AnyView(content()) }
    }
}

/// タブに並べる capsulet の一覧。新しいサブアプリはここに足す
enum CapsuletRegistry {
    static let all: [Capsulet] = [
        Capsulet(id: "fortuneMeal", title: "ごはんくじ", systemImage: "fork.knife") {
            FortuneMealView()
        },
    ]
}
