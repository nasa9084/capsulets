import AudioToolbox
import KanaKanjiConverterModuleWithDefaultDictionary
import SwiftUI
import UIKit

/// キーボードの状態と入力の処理。かな漢字変換は AzooKeyKanaKanjiConverter に任せる
final class KeyboardState: ObservableObject {
    enum Tab {
        case kana
        case number
    }

    @Published var tab: Tab = .kana
    @Published var needsGlobeKey = false
    @Published private(set) var candidates: [Candidate] = []
    @Published private(set) var isComposing = false

    /// 押している最中のキーの表示用
    let flick = FlickModel()

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

    func moveCursor(_ offset: Int) {
        playSound(.function)
        guard !isComposing else { return }
        proxy?.adjustTextPosition(byCharacterOffset: offset)
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
    private func refresh() {
        isComposing = true
        showMarkedText(composing.convertTarget)
        candidates = converter.requestCandidates(composing, options: options).mainResults
    }

    private func showMarkedText(_ text: String) {
        proxy?.setMarkedText(text, selectedRange: NSRange(location: (text as NSString).length, length: 0))
    }
}
