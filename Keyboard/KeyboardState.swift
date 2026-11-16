import AudioToolbox
import KanaKanjiConverterModuleWithDefaultDictionary
import SwiftUI
import UIKit

/// キーボードの状態と入力の処理。かな漢字変換は AzooKeyKanaKanjiConverter に任せる
final class KeyboardState: ObservableObject {
    enum Tab {
        case kana
        case english
        case number

        /// 切り替えキーに出す名前
        var title: String {
            switch self {
            case .kana: "あいう"
            case .english: "ABC"
            case .number: "☆123"
            }
        }
    }

    /// キーの配列。地球儀キーで切り替える
    enum Layout: String {
        case flick
        case qwerty
    }

    /// QWERTY のシフトの状態
    enum Shift {
        case off
        /// 次の 1 文字だけ大文字
        case once
        /// 大文字のまま
        case locked
    }

    private static let layoutKey = "keyboard.layout"

    @Published var tab: Tab = .kana
    /// 最後に使っていた配列を次回も使う
    @Published private(set) var layout =
        Layout(rawValue: UserDefaults.standard.string(forKey: layoutKey) ?? "") ?? .flick
    @Published private(set) var shift: Shift = .off
    /// QWERTY の数字記号のページ（0: 数字, 1: 記号）
    @Published private(set) var symbolPage = 0

    init() {
        // QWERTY には日本語がないので、英語から始める
        if layout == .qwerty {
            tab = .english
        }
    }
    @Published var needsGlobeKey = false
    @Published private(set) var candidates: [Candidate] = []
    @Published private(set) var isComposing = false

    /// 押している最中のキーの表示用
    let flick = FlickModel()
    /// 地球儀キーの長押しで出す定型文リスト
    let snippetMenu = SnippetMenuModel()

    weak var controller: UIInputViewController?

    private var proxy: (any UITextDocumentProxy)? { controller?.textDocumentProxy }
    /// 辞書の読み込みが走るので、最初の入力まで作らない
    private lazy var converter = KanaKanjiConverter.withDefaultDictionary()
    private var composing = ComposingText()

    private lazy var options: ConvertRequestOptions = {
        // 学習データの保存先（キーボード拡張機能自身の領域。フルアクセスなしで書ける）
        let directory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("KanaKanji", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return ConvertRequestOptions(
            N_best: 10,
            requireJapanesePrediction: true,
            requireEnglishPrediction: false,
            keyboardLanguage: .ja_JP,
            learningType: .inputAndOutput,
            memoryDirectoryURL: directory,
            sharedContainerURL: directory,
            textReplacer: .withDefaultEmojiDictionary(),
            specialCandidateProviders: KanaKanjiConverter.defaultSpecialCandidateProviders,
            zenzaiMode: .off, // Zenzai（ニューラル変換）を試すときはここを切り替える
            metadata: .init(versionString: "Capsulets Keyboard")
        )
    }()

    // MARK: - タイプ音

    /// iOS 標準キーボードと同じシステム音
    enum KeySound: SystemSoundID {
        /// 文字キー
        case input = 1104
        /// 削除キー
        case delete = 1155
        /// 空白・改行・切り替えなどの機能キー
        case function = 1156
    }

    /// タイプ音を鳴らす。キーボード拡張機能では「フルアクセスを許可」がオンのときだけ鳴らせる
    func playSound(_ sound: KeySound) {
        guard controller?.hasFullAccess == true else { return }
        AudioServicesPlaySystemSound(sound.rawValue)
    }

    // MARK: - キーからの入力

    /// かな・句読点など、変換の対象になる文字
    func inputKana(_ text: String) {
        playSound(.input)
        composing.insertAtCursorPosition(text, inputStyle: .direct)
        refresh()
    }

    /// 数字・記号など、そのまま入れる文字
    func inputDirect(_ text: String) {
        playSound(.input)
        commitAsIs()
        proxy?.insertText(text)
    }

    /// 定型文を入れる。入力中なら、ひらがなのまま確定してから入れる
    func insertSnippet(_ snippet: Snippet) {
        playSound(.input)
        commitAsIs()
        proxy?.insertText(snippet.text)
    }

    /// 切り替えキーを押したときの次のタブ。
    /// フリックは 日本語 → 英語 → 数字 → 日本語、QWERTY は日本語がなく 英語 ⇄ 数字
    var nextTab: Tab {
        switch tab {
        case .kana: .english
        case .english: .number
        case .number: layout == .flick ? .kana : .english
        }
    }

    func switchTab() {
        playSound(.function)
        commitAsIs()
        tab = nextTab
        shift = .off
        symbolPage = 0
    }

    /// フリックと QWERTY を切り替える
    func toggleLayout() {
        playSound(.function)
        commitAsIs()
        layout = layout == .flick ? .qwerty : .flick
        // QWERTY は英語から、フリックは日本語から始める
        tab = layout == .flick ? .kana : .english
        shift = .off
        symbolPage = 0
        UserDefaults.standard.set(layout.rawValue, forKey: Self.layoutKey)
    }

    // MARK: - QWERTY

    /// QWERTY の文字キー。打った文字をそのまま入れる
    func inputQwerty(_ key: String) {
        inputDirect(shift == .off ? key : key.uppercased())
        if shift == .once {
            shift = .off
        }
    }

    /// シフトなし → 次の 1 文字だけ大文字 → 大文字のまま → シフトなし
    func toggleShift() {
        playSound(.function)
        switch shift {
        case .off: shift = .once
        case .once: shift = .locked
        case .locked: shift = .off
        }
    }

    func toggleSymbolPage() {
        playSound(.function)
        symbolPage = symbolPage == 0 ? 1 : 0
    }

    /// 直前の英字の大文字・小文字を切り替える
    func toggleCaseOfLastCharacter() {
        playSound(.input)
        guard !isComposing, let last = proxy?.documentContextBeforeInput?.last, last.isLetter else { return }
        let lower = String(last).lowercased()
        let toggled = String(last) == lower ? String(last).uppercased() : lower
        guard toggled != String(last) else { return }
        proxy?.deleteBackward()
        proxy?.insertText(toggled)
    }

    /// 直前の文字を「小書き → 濁点 → 半濁点」の順に切り替える
    func modifyLastCharacter() {
        playSound(.input)
        guard isComposing,
              let last = composing.convertTargetBeforeCursor.last,
              let next = KanaTable.nextVariant(of: last)
        else { return }
        composing.deleteBackwardFromCursorPosition(count: 1)
        composing.insertAtCursorPosition(String(next), inputStyle: .direct)
        refresh()
    }

    func delete() {
        playSound(.delete)
        guard isComposing else {
            proxy?.deleteBackward()
            return
        }
        composing.deleteBackwardFromCursorPosition(count: 1)
        if composing.isEmpty {
            showMarkedText("")
            proxy?.unmarkText()
            finishComposition()
        } else {
            refresh()
        }
    }

    /// カーソルから行頭までを削除する。入力中は、入力中の文字をすべて消す
    func deleteToLineStart() {
        playSound(.delete)
        if isComposing {
            showMarkedText("")
            proxy?.unmarkText()
            finishComposition()
            return
        }
        deleteBackwardToLineStart(remainingPasses: 20, previous: nil)
    }

    /// iOS は一度にカーソルの近くの文字しか教えてくれないので、行頭に届くまで少しずつ消す
    private func deleteBackwardToLineStart(remainingPasses: Int, previous: String?) {
        guard remainingPasses > 0, let proxy, let before = proxy.documentContextBeforeInput else { return }
        if before == previous {
            // 前回の削除がまだ反映されていない。消しすぎないよう、もう少し待つ
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.deleteBackwardToLineStart(remainingPasses: remainingPasses - 1, previous: previous)
            }
            return
        }
        let line = before.split(separator: "\n", omittingEmptySubsequences: false).last ?? ""
        guard !line.isEmpty else { return }
        for _ in 0..<line.count {
            proxy.deleteBackward()
        }
        // 見えていた範囲に改行がなければ、まだ行の途中かもしれないので続きを確かめる
        if line.count == before.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.deleteBackwardToLineStart(remainingPasses: remainingPasses - 1, previous: before)
            }
        }
    }

    /// カーソルから行末までを削除する。すでに行末なら、次の改行を 1 つ消す
    func deleteToLineEnd() {
        playSound(.delete)
        guard !isComposing, let proxy, let after = proxy.documentContextAfterInput, !after.isEmpty else { return }
        let line = after.split(separator: "\n", omittingEmptySubsequences: false).first ?? ""
        let target = line.isEmpty ? "\n" : String(line)
        // 前に向かって消す API しかないので、カーソルを後ろへ動かしてから消す
        proxy.adjustTextPosition(byCharacterOffset: target.utf16.count)
        let count = target.count
        // カーソルの移動が反映されるのを少し待つ
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let proxy = self?.proxy else { return }
            for _ in 0..<count {
                proxy.deleteBackward()
            }
        }
    }

    /// 空白を入れる。入力中なら、ひらがなのまま確定してから入れる
    func space() {
        playSound(.function)
        commitAsIs()
        proxy?.insertText(" ")
    }

    /// 入力中は「確定」、そうでなければ改行
    func enter() {
        playSound(.function)
        guard isComposing else {
            proxy?.insertText("\n")
            return
        }
        commitAsIs()
    }

    /// カーソルを動かす。入力中は、変換する範囲（先頭からカーソルまで）を縮めたり伸ばしたりする
    func moveCursor(_ offset: Int) {
        playSound(.function)
        guard isComposing else {
            proxy?.adjustTextPosition(byCharacterOffset: offset)
            return
        }
        let moved = composing.moveCursorFromCursorPosition(count: offset)
        if composing.isAtStartIndex {
            // 範囲が空になるところまでは縮めない
            _ = composing.moveCursorFromCursorPosition(count: -moved)
            return
        }
        if moved != 0 {
            refresh()
        }
    }

    func nextKeyboard() {
        playSound(.function)
        commitAsIs()
        controller?.advanceToNextInputMode()
    }

    func dismissKeyboard() {
        playSound(.function)
        commitAsIs()
        controller?.dismissKeyboard()
    }

    // MARK: - 確定

    /// 候補をタップして確定する
    func tapCandidate(_ index: Int) {
        playSound(.function)
        choose(index)
    }

    private func choose(_ index: Int) {
        guard candidates.indices.contains(index) else { return }
        let candidate = candidates[index]
        showMarkedText(candidate.text)
        proxy?.unmarkText()
        converter.setCompletedData(candidate)
        converter.updateLearningData(candidate)
        composing.prefixComplete(composingCount: candidate.composingCount)
        if composing.isEmpty {
            finishComposition()
        } else {
            // 候補が入力の途中までだったときは、残りで変換を続ける
            refresh()
        }
    }

    /// 変換せず、ひらがなのまま確定する
    func commitAsIs() {
        guard isComposing else { return }
        showMarkedText(composing.convertTarget)
        proxy?.unmarkText()
        finishComposition()
    }

    private func finishComposition() {
        composing = ComposingText()
        candidates = []
        isComposing = false
        converter.stopComposition()
        converter.commitUpdateLearningData()
    }

    // MARK: - 表示

    /// 入力中の文字を下線付き（未確定）で出し直して、候補を取り直す
    /// 変換するのは先頭からカーソルまで。矢印キーでカーソルを動かすと、その範囲の候補に変わる
    private func refresh() {
        isComposing = true
        let target = composing.prefixToCursorPosition()
        let text = composing.convertTarget
        // 変換する範囲を選択状態にして見せる（範囲が全体のときは末尾にカーソルを置くだけ）
        let targetLength = (target.convertTarget as NSString).length
        let isWhole = composing.isAtEndIndex
        proxy?.setMarkedText(
            text,
            selectedRange: isWhole
                ? NSRange(location: (text as NSString).length, length: 0)
                : NSRange(location: 0, length: targetLength)
        )
        candidates = converter.requestCandidates(target, options: options).mainResults
    }

    private func showMarkedText(_ text: String) {
        proxy?.setMarkedText(text, selectedRange: NSRange(location: (text as NSString).length, length: 0))
    }
}
