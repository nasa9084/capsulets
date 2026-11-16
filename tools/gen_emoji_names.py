"""絵文字の名前の表（Keyboard/EmojiNameData.swift）を作る。

npm の emojibase-data から、Slack（iamcal）と GitHub の名前（:thinking_face: の中身）を取り出す。
肌の色の違いは含めない。リポジトリのルートで実行する:
    npm pack emojibase-data && tar xzf emojibase-data-*.tgz
    python3 tools/gen_emoji_names.py package/en
"""
import json
import sys

base = sys.argv[1]
emojis = json.load(open(f"{base}/data.json"))
sources = [json.load(open(f"{base}/shortcodes/{name}.json")) for name in ("iamcal", "github")]

lines = []
seen = set()
for entry in emojis:
    for source in sources:
        names = source.get(entry["hexcode"], [])
        for name in [names] if isinstance(names, str) else names:
            assert " " not in name and '"' not in name and "\\" not in name, name
            if name not in seen:  # 同じ名前が別の絵文字に付いていたら、先に出たほうを使う
                seen.add(name)
                lines.append(f"{name} {entry['emoji']}")

out = [
    "// tools/gen_emoji_names.py で生成したファイル。手で編集しない",
    "",
    "/// 絵文字の名前の表。1 行が「名前 絵文字」",
    "enum EmojiNameData {",
    '    static let table = """',
    *[f"    {line}" for line in lines],
    '    """',
    "}",
]
open("Keyboard/EmojiNameData.swift", "w").write("\n".join(out) + "\n")
print(len(lines))
