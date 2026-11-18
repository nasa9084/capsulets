import SwiftUI
import UIKit

/// キーボード拡張機能の入口。SwiftUI のキーボード画面を載せる
final class KeyboardViewController: UIInputViewController {
    private let state = KeyboardState()

    override func viewDidLoad() {
        super.viewDidLoad()
        state.controller = self

        let host = UIHostingController(rootView: KeyboardView(state: state))
        host.view.backgroundColor = .clear
        // iOS がキーボードの上端に取る余白（セーフエリア）の分、中身が下がらないようにする
        host.safeAreaRegions = []
        host.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(host)
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)

        // 高さは自分で決める（iOS の既定の高さに引き伸ばされないようにする）
        (view as? UIInputView)?.allowsSelfSizing = true
        let height = view.heightAnchor.constraint(equalToConstant: KeyboardView.totalHeight)
        height.priority = UILayoutPriority(999)
        height.isActive = true
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        state.reloadSettings()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        // ホームボタンのない機種では地球儀キーを iOS が下に出すので、自前では出さない
        if state.needsGlobeKey != needsInputModeSwitchKey {
            state.needsGlobeKey = needsInputModeSwitchKey
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // 入力途中でキーボードが閉じたら、ひらがなのまま確定する
        state.commitAsIs()
    }
}
