# 公欠申請 Claude Code Skill

学生ポータルへの公欠申請を Claude Code の `/absence` コマンドで半自動化するSkillです。

## 必要なもの

- [Claude Code](https://claude.ai/code)
- `curl`

---

## セットアップ

### 1. リポジトリをクローン

```bash
git clone <repository-url>
cd <repository-name>
```

### 2. 環境変数を設定

```bash
cp .env.example .env
```

`.env` を編集して以下を設定してください:

```env
STUDENT_PORTAL_URL=https://your-school-portal.example.com
STUDENT_PORTAL_PHPSESSID=your_phpsessid_here
```

> **PHPSESSID の取得方法:** ブラウザでポータルにログイン後、開発者ツール → Application → Sessions から `PHPSESSID` の値をコピーしてください。

### 3. 時間割を設定

`data/timetable.example.md` を参考に `data/timetable.md` を作成してください:

```bash
cp data/timetable.example.md data/timetable.md
```

`data/timetable.md` を自分の時間割に編集してください。フォーマット:

```markdown
### 月曜日

- 1限/授業名/講師名先生
- 2限/授業名/講師名先生
```

### 4. スクリプトに実行権限を付与

```bash
chmod +x scripts/run.sh scripts/submit.sh
```

---

## 使い方

Claude Code を起動し、`/absence` と入力してください。

```
/absence
```

あとは対話に従って進めるだけです:

1. **日付入力** — 公欠を申請する日付を入力（例: `2026-07-04`）
2. **授業選択** — 該当日の授業が一覧表示されるので番号を選択（複数可）
3. **証明写真** — ファイルパスを入力（任意）
4. **理由入力** — 自分で入力 or 写真をもとにClaudeが自動生成
5. **申請実行** — 自動的にポータルへ送信
6. **ログ保存** — `logs/log/` に申請内容が保存されます

---

## ファイル構成

```
.
├── .claude/
│   └── commands/
│       └── absence.md      # /absence コマンド定義
├── data/
│   ├── timetable.md        # 自分の時間割（.gitignore対象）
│   ├── timetable.example.md
│   └── weekdays.md         # 授業がある曜日
├── scripts/
│   ├── run.sh              # .env読み込みラッパー
│   └── submit.sh           # ポータルへのHTTP POSTスクリプト
├── logs/
│   └── log/                # 申請ログ（.gitignore対象）
├── .env                    # 環境変数（.gitignore対象）
└── .env.example
```

---

## 注意事項

- `data/timetable.md` と `.env` は `.gitignore` に含まれているためコミットされません
