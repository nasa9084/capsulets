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
    /// 英単語の補完の候補（QWERTY の英字で、単語を打っている間だけ出す）
    @Published private(set) var completions: [String] = []
    /// 打ちかけの英単語
    private var englishWord = ""
    private var didInsertSpaceAfterCompletion = false
    /// 「:」のあとに打っている絵文字の名前（nil は打っていない）
    private var emojiQuery: String?
    /// 候補バーに出している、名前に合う絵文字
    private var emojiMatches: [EmojiNames.Entry] = []
    private let textChecker = UITextChecker()

    /// 候補バーに出す文字。入力中は変換候補、そうでなければ英単語の補完
    var barItems: [String] {
        isComposing ? candidates.map(\.text) : completions
    }

    func tapBarItem(_ index: Int) {
        if isComposing {
            tapCandidate(index)
        } else {
            tapCompletion(index)
        }
    }

    /// 絵文字の一覧
    let emoji = EmojiModel()
    @Published private(set) var isEmojiVisible = false
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
        resetCompletion()
        composing.insertAtCursorPosition(text, inputStyle: .direct)
        refresh()
    }

    /// 数字・記号など、そのまま入れる文字
    func inputDirect(_ text: String) {
        playSound(.input)
        resetCompletion(keepsEmojiQuery: true)
        commitAsIs()
        if replaceEmojiName(closingWith: text) {
            return
        }
        proxy?.insertText(text)
        if emojiQuery != nil || !emojiMatches.isEmpty {
            updateCompletions()
        }
    }

    /// フリックの英字キー。シフト中の大文字はキーの側で付けてあるので、そのまま入れてシフトを戻す
    func inputFlickEnglish(_ text: String) {
        inputDirect(text)
        if shift == .once {
            shift = .off
        }
    }

    /// 定型文を入れる。入力中なら、ひらがなのまま確定してから入れる
    func insertSnippet(_ snippet: Snippet) {
        playSound(.input)
        resetCompletion()
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
        // 「:」と名前でページを行き来するので、絵文字の名前の入力は続ける
        resetCompletion(keepsEmojiQuery: true)
        commitAsIs()
        tab = nextTab
        shift = .off
        symbolPage = 0
    }

    /// フリックと QWERTY を切り替える
    func toggleLayout() {
        playSound(.function)
        resetCompletion()
        commitAsIs()
        layout = layout == .flick ? .qwerty : .flick
        // QWERTY は英語から、フリックは日本語から始める
        tab = layout == .flick ? .kana : .english
        shift = .off
        symbolPage = 0
        UserDefaults.standard.set(layout.rawValue, forKey: Self.layoutKey)
    }

    // MARK: - 絵文字

    func openEmoji() {
        playSound(.function)
        resetCompletion()
        commitAsIs()
        emoji.open()
        isEmojiVisible = true
    }

    func closeEmoji() {
        playSound(.function)
        isEmojiVisible = false
    }

    func inputEmoji(_ text: String) {
        playSound(.input)
        resetCompletion()
        proxy?.insertText(text)
        emoji.record(text)
    }

    // MARK: - QWERTY

    /// QWERTY の文字キー。打った文字をそのまま入れる
    func inputQwerty(_ key: String) {
        let text = shift == .off ? key : key.uppercased()
        let word = englishWord
        // 補完で入れた空白のすぐあとに句読点を打ったら、空白を取り除く（"word ." にしない）
        if didInsertSpaceAfterCompletion, ".,?!:;".contains(key) {
            proxy?.deleteBackward()
        }
        inputDirect(text)
        if tab == .english, key.first?.isLetter == true {
            englishWord = word + text
            updateCompletions()
        }
        if shift == .once {
            shift = .off
        }
    }

    // MARK: - 英単語の補完（QWERTY の英字）

    /// 補完の候補をタップしたとき。打ちかけの単語を候補に置き換えて、空白を入れる
    func tapCompletion(_ index: Int) {
        guard completions.indices.contains(index) else { return }
        playSound(.function)
        if emojiMatches.indices.contains(index), let query = emojiQuery {
            // 「:名前」を絵文字に置き換える
            let emoji = emojiMatches[index].emoji
            for _ in 0..<(query.count + 1) {
                proxy?.deleteBackward()
            }
            proxy?.insertText(emoji)
            self.emoji.record(emoji)
            resetCompletion()
            return
        }
        let completion = completions[index]
        for _ in 0..<englishWord.count {
            proxy?.deleteBackward()
        }
        proxy?.insertText(completion + " ")
        resetCompletion()
        didInsertSpaceAfterCompletion = true
    }

    private func resetCompletion(keepsEmojiQuery: Bool = false) {
        if !keepsEmojiQuery {
            emojiQuery = nil
            emojiMatches = []
        }
        englishWord = ""
        didInsertSpaceAfterCompletion = false
        if !completions.isEmpty {
            completions = []
        }
    }

    /// iOS の辞書から、打ちかけの単語の続きと、つづり間違いの直し方の候補を取る
    private func updateCompletions() {
        // 「:名前」を打っている間は、名前に合う絵文字を出す
        if let query = emojiQuery, query.count >= 2 {
            emojiMatches = EmojiNames.search(query, limit: 40)
                .filter { EmojiModel.isSupported($0.emoji) }
                .prefix(20)
                .map { $0 }
            completions = emojiMatches.map { "\($0.emoji) \($0.name)" }
            return
        }
        emojiMatches = []
        guard !englishWord.isEmpty else {
            completions = []
            return
        }
        let word = englishWord
        let range = NSRange(location: 0, length: (word as NSString).length)
        var results = textChecker.completions(forPartialWordRange: range, in: word, language: "en_US") ?? []
        let misspelled = textChecker.rangeOfMisspelledWord(
            in: word, range: range, startingAt: 0, wrap: false, language: "en_US"
        )
        if misspelled.location != NSNotFound {
            results += textChecker.guesses(forWordRange: range, in: word, language: "en_US") ?? []
        }
        // 打った文字の大文字・小文字に合わせる
        let isAllUppercase = word.count > 1 && word == word.uppercased()
        let isCapitalized = word.first?.isUppercase == true
        var seen = Set<String>()
        completions = results
            .map { isAllUppercase ? $0.uppercased() : isCapitalized ? $0.prefix(1).uppercased() + $0.dropFirst() : $0 }
            .filter { $0 != word && seen.insert($0).inserted }
            .prefix(12)
            .map { String($0) }
    }

    // MARK: - 絵文字の名前入力（:thinking_face:）

    /// 「:」のあとに打った文字を覚える。閉じの「:」で名前がぴったり合えば、絵文字に置き換えて true を返す
    private func replaceEmojiName(closingWith text: String) -> Bool {
        if text == ":" {
            if let query = emojiQuery, let emoji = EmojiNames.emoji(named: query), EmojiModel.isSupported(emoji) {
                for _ in 0..<(query.count + 1) {
                    proxy?.deleteBackward()
                }
                proxy?.insertText(emoji)
                self.emoji.record(emoji)
                resetCompletion()
                return true
            }
            emojiQuery = ""
            return false
        }
        guard let query = emojiQuery else { return false }
        let lowered = text.lowercased()
        let isNameCharacter = lowered.count == 1 && lowered.unicodeScalars.allSatisfy {
            ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "_" || $0 == "+" || $0 == "-"
        }
        // 「12:30」のような時刻で候補を出さないよう、数字で始まる名前は対象にしない
        let startsWithDigit = query.isEmpty && lowered.first?.isNumber == true
        emojiQuery = isNameCharacter && !startsWithDigit ? query + lowered : nil
        return false
    }

    /// カーソルの直前にある英字の並びを、打ちかけの単語として読み直す
    private func reloadEnglishWord() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self, !self.isComposing, self.layout == .qwerty, self.tab == .english,
                  let before = self.proxy?.documentContextBeforeInput
            else { return }
            let letters = before.reversed().prefix { $0.isASCII && $0.isLetter }
            self.englishWord = String(letters.reversed())
            self.updateCompletions()
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
            didInsertSpaceAfterCompletion = false
            if let query = emojiQuery {
                // 名前を 1 文字戻す。「:」まで消したら名前の入力をやめる
                emojiQuery = query.isEmpty ? nil : String(query.dropLast())
                updateCompletions()
            }
            if layout == .qwerty, tab == .english {
                if englishWord.isEmpty {
                    // 打ちかけの単語を見失っているので、入力欄から読み直す
                    reloadEnglishWord()
                } else {
                    englishWord.removeLast()
                    updateCompletions()
                }
            }
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
        resetCompletion()
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
        resetCompletion()
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
        resetCompletion()
        commitAsIs()
        proxy?.insertText(" ")
    }

    /// 入力中は「確定」、そうでなければ改行
    func enter() {
        playSound(.function)
        resetCompletion()
        guard isComposing else {
            proxy?.insertText("\n")
            return
        }
        commitAsIs()
    }

    /// カーソルを動かす。入力中は、変換する範囲（先頭からカーソルまで）を縮めたり伸ばしたりする
    func moveCursor(_ offset: Int) {
        playSound(.function)
        resetCompletion()
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
        resetCompletion()
        commitAsIs()
        controller?.advanceToNextInputMode()
    }

    func dismissKeyboard() {
        playSound(.function)
        resetCompletion()
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
        commitMarkedText(as: candidate.text)
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
        commitMarkedText(as: composing.convertTarget)
        finishComposition()
    }

    /// 未確定の文字を、指定した文字に置き換えて確定する。
    /// 「setMarkedText → unmarkText」で確定すると、直後に残りを未確定で出し直したとき（部分確定）に
    /// 確定が後回しになり、確定した文字が消えて残りが確定されてしまう。
    /// insertText は未確定の文字を置き換えて確定するので、こちらを使う
    private func commitMarkedText(as text: String) {
        proxy?.insertText(text)
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
