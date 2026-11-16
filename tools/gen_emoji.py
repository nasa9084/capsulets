"""絵文字の一覧（Keyboard/EmojiData.swift）を作る。

npm の unicode-emoji-json（Unicode の絵文字データを JSON にしたもの）から、カテゴリごとの並びを取り出す。
肌の色の違いは含めない。リポジトリのルートで実行する:
    npm pack unicode-emoji-json && tar xzf unicode-emoji-json-*.tgz
    python3 tools/gen_emoji.py package/data-by-group.json
"""
import json
import sys

# アプリ側のカテゴリ → 元データのグループ名
CATEGORIES = [
    ("smileys", ["Smileys & Emotion", "People & Body"]),
    ("animals", ["Animals & Nature"]),
    ("food", ["Food & Drink"]),
    ("activities", ["Activities"]),
    ("travel", ["Travel & Places"]),
    ("objects", ["Objects"]),
    ("symbols", ["Symbols"]),
    ("flags", ["Flags"]),
]

groups = {g["name"]: [e["emoji"] for e in g["emojis"]] for g in json.load(open(sys.argv[1]))}

lines = [
    "// tools/gen_emoji.py で生成したファイル。手で編集しない",
    "",
    "/// カテゴリごとの絵文字（空白区切り）。肌の色の違いは含めない",
    "enum EmojiData {",
]
for name, sources in CATEGORIES:
    emojis = [e for source in sources for e in groups[source]]
    assert all(" " not in e and '"' not in e and "\\" not in e for e in emojis)
    lines.append(f'    static let {name} = "{" ".join(emojis)}"')
lines.append("}")
open("Keyboard/EmojiData.swift", "w").write("\n".join(lines) + "\n")
