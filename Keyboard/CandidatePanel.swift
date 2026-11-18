import SwiftUI

/// 変換候補をキーボード全体に広げた一覧。入力中に「変換」キーで開く。
/// 上に入力中の文字（変換する範囲を強調）、真ん中に候補、下に範囲の調整・次候補・確定
struct CandidatePanel: View {
    @ObservedObject var state: KeyboardState

    private static let bottomBarHeight: CGFloat = 50
    private let columns = [GridItem(.flexible(), spacing: 1), GridItem(.flexible(), spacing: 1)]

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(height: KeyboardView.candidateBarHeight)
            ScrollViewReader { reader in
                ScrollView(.vertical) {
                    LazyVGrid(columns: columns, spacing: 1) {
                        ForEach(Array(state.candidates.enumerated()), id: \.offset) { index, candidate in
                            Button {
                                state.tapCandidate(index)
                            } label: {
                                Text(candidate.text)
                                    .font(.system(size: 20))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.6)
                                    .foregroundStyle(state.selectedCandidate == index ? Color.white : Color.primary)
                                    .padding(.horizontal, 10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .frame(height: 46)
                                    .background(state.selectedCandidate == index ? state.accent : KeyColor.normal)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .id(index)
                        }
                    }
                }
                .background(KeyColor.function.opacity(0.4))
                .onChange(of: state.selectedCandidate) { _, index in
                    if let index {
                        reader.scrollTo(index, anchor: .center)
                    }
                }
            }
            bottomBar
                .frame(height: Self.bottomBarHeight)
        }
    }

    /// 入力中の文字。変換する範囲を色付きで見せる
    private var header: some View {
        HStack(spacing: 0) {
            let rest = String(state.composingText.dropFirst(state.targetText.count))
            (Text(state.targetText).foregroundStyle(Color.white) + Text(rest).foregroundStyle(Color.primary))
                .font(.system(size: 18))
                .lineLimit(1)
                .background(alignment: .leading) {
                    // 範囲の部分だけ背景を付ける
                    Text(state.targetText)
                        .font(.system(size: 18))
                        .foregroundStyle(.clear)
                        .background(state.accent)
                }
                .padding(.horizontal, 10)
            Spacer()
            Button {
                state.closeCandidatePanel()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.primary)
                    .frame(width: 44, height: KeyboardView.candidateBarHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .background(Color(uiColor: .systemBackground))
    }

    private var bottomBar: some View {
        HStack(spacing: 1) {
            FunctionKey(label: .symbol("arrow.left.to.line")) { state.moveCursor(-1) }
            FunctionKey(label: .symbol("arrow.right.to.line")) { state.moveCursor(1) }
            FunctionKey(label: .text("次候補")) { state.nextCandidate() }
                .frame(maxWidth: .infinity)
                .layoutPriority(1)
            FunctionKey(label: .text("確定"), isProminent: true) { state.enter() }
                .frame(maxWidth: .infinity)
                .layoutPriority(1)
        }
    }
}
