import SwiftUI
import UIKit

/// キーボード拡張機能の入口。SwiftUI のキーボード画面を載せる
final class KeyboardViewController: UIInputViewController {
    private let state = KeyboardState()
    /// キーボードの画面。閉じたあとも iOS 側に残ることがあるので、終了時に中身を空にして state を手放す
    private var host: UIHostingController<AnyView>?
    /// 読み込んでから表示されるまでの時間を測る
    private var loadedAt = Date()

    override func viewDidLoad() {
        super.viewDidLoad()
        loadedAt = Date()
        KeyboardLog.sessionStarted()
        KeyboardLog.add("読み込み（フルアクセス: \(hasFullAccess ? "オン" : "オフ")）")
        state.controller = self

        // 中身は表示の直前に入れる（iOS は表示しないキーボードを作って残しておくことがあるので、その分を軽くする）
        let host = UIHostingController(rootView: AnyView(EmptyView()))
        self.host = host
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
        let proxy = textDocumentProxy
        let contentType = proxy.textContentType.map { $0?.rawValue ?? "なし" } ?? "なし"
        KeyboardLog.add("表示の準備（入力欄の種類: \(Self.keyboardTypeName(proxy.keyboardType ?? .default))、内容: \(contentType)）")
        Self.visibleCount += 1
        if !isShowingKeyboard {
            isShowingKeyboard = true
            host?.rootView = AnyView(KeyboardView(state: state))
        }
        state.reloadSettings()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        let elapsed = Int(Date().timeIntervalSince(loadedAt) * 1000)
        KeyboardLog.add("表示（読み込みから \(elapsed)ms、高さ \(Int(view.bounds.height))pt）")
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // 警告は残っているキーボードの数だけ同時に届くので、ログは全体で 5 秒に 1 回にする
        if Date().timeIntervalSince(Self.lastMemoryWarningLog) > 5 {
            Self.lastMemoryWarningLog = Date()
            KeyboardLog.add("⚠️ iOS からメモリ不足の警告")
        }
        state.releaseMemory(reason: "メモリ不足の警告", includingConverter: true)
    }

    private static var lastMemoryWarningLog = Date.distantPast
    /// いま表示されているキーボードの数
    private static var visibleCount = 0
    /// 閉じたときにメモリがこれを超えていたら、キーボードを終了して次回まっさらな状態で起動し直す（上限は約 150MB）
    private static let restartThresholdMB: Double = 90
    private var isShowingKeyboard = false

    /// 入力欄の中身がアプリ側で変わったとき（送信して欄が空になったときなど）
    override func textDidChange(_ textInput: (any UITextInput)?) {
        super.textDidChange(textInput)
        state.handleExternalTextChange()
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
        KeyboardLog.add("閉じる")
        // 入力途中でキーボードが閉じたら、ひらがなのまま確定する
        state.commitAsIs()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        KeyboardLog.add("閉じた")
        Self.visibleCount = max(0, Self.visibleCount - 1)
        state.releaseMemory(reason: "閉じた", includingConverter: false)
        // 閉じたあとも iOS がこの画面を残すことがあるので、SwiftUI の中身を外しておく
        if isShowingKeyboard {
            isShowingKeyboard = false
            host?.rootView = AnyView(EmptyView())
        }
        KeyboardLog.sessionEnded()
        Self.restartIfMemoryIsHigh()
    }

    /// メモリが増えすぎていたら、表示中のキーボードがないのを確かめてからプロセスを終了する。
    /// 次にキーボードを開くと iOS がまっさらな状態で起動し直すので、入力中に強制終了されるより安全
    private static func restartIfMemoryIsHigh() {
        guard let mb = KeyboardLog.memoryMB(), mb > restartThresholdMB else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            guard visibleCount == 0, let mb = KeyboardLog.memoryMB(), mb > restartThresholdMB else { return }
            KeyboardLog.add("メモリが \(Int(mb))MB まで増えたので、キーボードを終了して起動し直す")
            KeyboardLog.sessionEnded()
            KeyboardLog.flush()
            exit(0)
        }
    }

    /// 入力欄が求めるキーボードの種類（電話番号の欄などでは iOS が標準のキーボードに切り替えることがある）
    private static func keyboardTypeName(_ type: UIKeyboardType) -> String {
        switch type {
        case .default: "標準"
        case .asciiCapable: "英数字"
        case .numbersAndPunctuation: "数字と記号"
        case .URL: "URL"
        case .numberPad: "数字"
        case .phonePad: "電話番号"
        case .namePhonePad: "名前と電話番号"
        case .emailAddress: "メールアドレス"
        case .decimalPad: "小数"
        case .twitter: "Twitter"
        case .webSearch: "Web 検索"
        case .asciiCapableNumberPad: "英数字の数字"
        @unknown default: "その他(\(type.rawValue))"
        }
    }

    deinit {
        KeyboardLog.add("終了")
        // 画面（SwiftUI）が state を握ったまま残ると、変換エンジンごとメモリに残り続ける。
        // 画面の中身を空にし、state が持っている大きなものも先に手放しておく
        MainActor.assumeIsolated {
            host?.rootView = AnyView(EmptyView())
            host = nil
            state.tearDown()
        }
        KeyboardLog.sessionEnded()
    }
}
