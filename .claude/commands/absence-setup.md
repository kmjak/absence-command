`/absence` と `/absence-list` を使えるようにするための初期セットアップ手順です。
`/absence setup`（または `/absence-setup`）から呼ばれます。

環境チェック・設定ファイルの作成・ポータルへの疎通確認までを対話で案内します。

`$ARGUMENTS` に `--check` が含まれる場合は **Step 1 の診断だけを実行して結果を表示し、終了**してください
（設定を変更せず現状確認だけしたいとき用）。

---

## Step 1: 環境診断

まず現状を把握します。以下を実行して結果をそのままユーザーに提示してください。

```bash
./scripts/absence_setup.sh
```

出力は `OK` / `WARN` / `NG` の3種類です。

| 表示 | 意味 | 対応 |
|------|------|------|
| `OK` | 問題なし | 何もしない |
| `WARN` | 動くが確認が必要（雛形のままの時間割など） | Step 3 以降で埋める |
| `NG` | このままでは動かない | Step 2 以降で解消する |

`RESULT ok` かつ `WARN` も無い場合は、Step 2〜4 をスキップして **Step 5** へ進んでください。

`--check` が指定されている場合はここで終了します。

---

## Step 2: 自動で直せるものを直す

`NG` に以下のいずれかが含まれていた場合は、`--fix` で自動修復してください。

- `env:file`（`.env` が無い）
- `env:STUDENT_PORTAL_PHPSESSID`（未設定 / 雛形のまま）※URL・ID・パスワードが設定済みの場合のみ
- `data:timetable`（`data/timetable.md` が無い）
- `logs:dir`（`logs/log` が無い）
- `exec:*`（スクリプトの実行権限が無い）

```bash
./scripts/absence_setup.sh --fix
```

`--fix` は雛形のコピー・`mkdir`・`chmod +x`・**PHPSESSID の自動取得**を行い、
**既存ファイルは上書きしません**（`.env` も PHPSESSID の行だけを差し替えます）。

`.env` に URL・ログインID・パスワードがまだ無い状態では PHPSESSID を取得できません。
その場合は Step 3 で先にそれらを設定してから、もう一度 `--fix` を実行してください。

`cmd:*` の `NG`（`curl` / `jq` / `python3` / `base64` / `file` が無い）は自動修復できません。
表示されたインストールコマンド（macOS なら `brew install <コマンド名>`）をユーザーに案内し、
インストールが済んでから再度 `/absence setup` を実行してもらってください。

---

## Step 3: `.env` の設定

`env:STUDENT_PORTAL_*` に `NG`（未設定 or 雛形のまま）が残っている項目についてのみ、
以下を1つずつ聞いて `.env` を更新してください。既に `OK` の項目は聞かないでください。

```
学生ポータルのURLを入力してください（例: https://portal.example.ac.jp）:
学生ポータルのログインID（学籍番号）を入力してください:
学生ポータルのパスワードを入力してください:
```

入力された値で `.env` の該当行を書き換えてください（`.env` は `.gitignore` 対象なのでコミットされません）。
**入力されたパスワードや PHPSESSID を会話の応答に出力しないでください。**

### `STUDENT_PORTAL_PHPSESSID` はユーザーに聞かないこと（重要）

**PHPSESSID は自動取得します。ブラウザの開発者ツールから値をコピーしてもらう必要はありません。**
上の3項目を `.env` に書き込んだあと、以下を実行してください:

```bash
./scripts/session.sh
```

`scripts/session.sh` はポータルのログインAPIを Cookie なしで叩いて
サーバに新しいセッションを発行させ（`Set-Cookie: PHPSESSID=...`）、
その値で疎通確認をしたうえで `.env` の `STUDENT_PORTAL_PHPSESSID` の行だけを書き換えます。
セッションIDは標準出力に出ないので、**取得した値を会話に表示しないでください**。

`./scripts/absence_setup.sh --fix` を実行した場合はこの取得も一緒に行われるため、
Step 2 で `--fix` を実行済みで `env:STUDENT_PORTAL_PHPSESSID` が `OK` になっていれば、
このステップで改めて `session.sh` を実行する必要はありません。

`session.sh` が失敗した場合はログインID / パスワード / URL の誤りを疑い、
Step 3 の3項目を聞き直してから再実行してください。

---

## Step 4: 時間割の設定

`data:timetable` が `WARN`（example と同一）または新規作成直後の場合のみ実行してください。

`data/timetable.example.md` の形式を提示したうえで、自分の時間割を書くよう案内してください:

```markdown
### 月曜日

- 1限/ネットワーク演習Ⅱ/山本先生
- 2限/ネットワーク演習Ⅱ/山本先生
```

- 授業がない曜日は見出しごと省略して構いません。
- ユーザーが会話で時間割を伝えてきた場合は、この形式に整形して `data/timetable.md` に書き込んでください。
- 授業がある曜日が `data/weekdays.md` の内容と食い違っている場合は、`data/weekdays.md` も合わせて更新してください。

---

## Step 5: 疎通確認

ここまでの設定が実際に動くかを、ポータルへの通信込みで確認してください。

```bash
./scripts/absence_setup.sh --probe
```

PHPSESSID の期限が切れていた場合は、`--fix` が付いていればその場で取り直して再試行します。
そのため疎通確認は `--fix` と併せて実行するのが確実です:

```bash
./scripts/absence_setup.sh --fix --probe
```

`portal:probe` が `OK` なら成功です。`NG` の場合は以下を疑って案内してください:

1. `STUDENT_PORTAL_URL` の誤り（末尾に `/` を付けていないか）
2. ログインID / パスワードの誤り

PHPSESSID を明示的に取り直したいときは以下が使えます:

```bash
./scripts/absence_setup.sh --session   # 取り直して .env に設定し、他のチェックも実行
./scripts/session.sh                   # 取り直しだけを行う
```

---

## Step 6: 完了サマリ

最後に以下の形式で結果をまとめて提示してください。

```
セットアップ完了

  必要なコマンド      OK
  .env                OK
  PHPSESSID           OK（自動取得済み）
  時間割              OK（12コマ）
  スクリプト権限      OK
  ポータル疎通        OK

次に使えるコマンド:
  /absence-list   欠席になっている日付の一覧を表示
  /absence        公欠申請を行う（写真添付あり）
```

未完了の項目が残っている場合は、その項目と「次に何をすればよいか」を明示してください。
