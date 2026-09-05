#!/bin/bash

# `/absence setup` の環境チェック用スクリプト。
# 必要なコマンド・設定ファイル・実行権限が揃っているかを確認して結果を一覧表示する。
#
# 使い方:
#   scripts/absence_setup.sh          チェックのみ（何も変更しない。--check も同じ）
#   scripts/absence_setup.sh --fix    自動で直せるもの（雛形コピー・chmod・ディレクトリ作成）を直してから再チェック
#   scripts/absence_setup.sh --probe  上記に加えてポータルへの疎通確認まで行う（ネットワークアクセスあり）
#
# 出力フォーマット（1行1項目）:
#   OK   <ID>  <メッセージ>     問題なし
#   NG   <ID>  <メッセージ>     このままでは動かない
#   WARN <ID>  <メッセージ>     動くが確認が必要
#
# 終了コード:
#   0  NG なし
#   1  NG あり

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

FIX=0
PROBE=0
for arg in "$@"; do
  case "$arg" in
    --check) ;;  # チェックのみ（デフォルト動作）。明示指定できるようにしてあるだけ
    --fix)   FIX=1 ;;
    --probe) PROBE=1 ;;
    *) echo "不明なオプション: $arg" >&2; exit 2 ;;
  esac
done

NG_COUNT=0

ok()   { printf 'OK   %-28s %s\n' "$1" "$2"; }
warn() { printf 'WARN %-28s %s\n' "$1" "$2"; }
ng()   { printf 'NG   %-28s %s\n' "$1" "$2"; NG_COUNT=$((NG_COUNT + 1)); }

echo "=== 必要なコマンド ==="
for cmd in curl jq python3 base64 file; do
  if command -v "$cmd" > /dev/null 2>&1; then
    ok "cmd:$cmd" "$(command -v "$cmd")"
  else
    ng "cmd:$cmd" "見つかりません（macOS なら: brew install ${cmd}）"
  fi
done

echo
echo "=== 設定ファイル ==="

# .env
if [ ! -f "$ROOT/.env" ]; then
  if [ "$FIX" = "1" ] && [ -f "$ROOT/.env.example" ]; then
    cp "$ROOT/.env.example" "$ROOT/.env"
    warn "env:file" ".env.example から .env を作成しました（中身は雛形なので要編集）"
  else
    ng "env:file" ".env がありません（cp .env.example .env）"
  fi
else
  ok "env:file" ".env"
fi

if [ -f "$ROOT/.env" ]; then
  # .env をサブシェルで読んで値だけ確認する（呼び出し元の環境は汚さない）
  while IFS='=' read -r key expected_dummy; do
    value="$(grep -E "^${key}=" "$ROOT/.env" | head -1 | cut -d= -f2- \
      | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'\$/\1/")"
    if [ -z "$value" ]; then
      ng "env:$key" "未設定です"
    elif [ "$value" = "$expected_dummy" ]; then
      ng "env:$key" "雛形のままです（実際の値に書き換えてください）"
    else
      ok "env:$key" "設定済み"
    fi
  done <<'KEYS'
STUDENT_PORTAL_URL=https://example.com
STUDENT_PORTAL_PHPSESSID=example_session_id
STUDENT_PORTAL_USER_ID=your_student_id
STUDENT_PORTAL_PASSWORD=your_password
KEYS
fi

# timetable.md
if [ ! -f "$ROOT/data/timetable.md" ]; then
  if [ "$FIX" = "1" ] && [ -f "$ROOT/data/timetable.example.md" ]; then
    cp "$ROOT/data/timetable.example.md" "$ROOT/data/timetable.md"
    warn "data:timetable" "example から作成しました（自分の時間割に書き換えてください）"
  else
    ng "data:timetable" "data/timetable.md がありません（cp data/timetable.example.md data/timetable.md）"
  fi
elif diff -q "$ROOT/data/timetable.md" "$ROOT/data/timetable.example.md" > /dev/null 2>&1; then
  warn "data:timetable" "example と同一です（自分の時間割に書き換えてください）"
else
  ok "data:timetable" "$(grep -cE '^- [0-9]+限/' "$ROOT/data/timetable.md" || echo 0) コマ登録済み"
fi

# weekdays.md
if [ -f "$ROOT/data/weekdays.md" ]; then
  ok "data:weekdays" "$(grep -cE '^- .*曜日' "$ROOT/data/weekdays.md" || echo 0) 曜日登録済み"
else
  ng "data:weekdays" "data/weekdays.md がありません"
fi

# logs/log
if [ -d "$ROOT/logs/log" ]; then
  ok "logs:dir" "logs/log"
elif [ "$FIX" = "1" ]; then
  mkdir -p "$ROOT/logs/log"
  ok "logs:dir" "logs/log を作成しました"
else
  ng "logs:dir" "logs/log がありません（mkdir -p logs/log）"
fi

echo
echo "=== スクリプトの実行権限 ==="
for s in login.sh run.sh submit.sh attendance.sh absence_list.sh absence_setup.sh; do
  path="$ROOT/scripts/$s"
  if [ ! -f "$path" ]; then
    ng "exec:$s" "ファイルがありません"
  elif [ -x "$path" ]; then
    ok "exec:$s" "実行可能"
  elif [ "$FIX" = "1" ]; then
    chmod +x "$path"
    ok "exec:$s" "実行権限を付与しました"
  else
    ng "exec:$s" "実行権限がありません（chmod +x scripts/${s}）"
  fi
done

if [ "$PROBE" = "1" ]; then
  echo
  echo "=== ポータル疎通確認 ==="
  if [ "$NG_COUNT" -gt 0 ]; then
    warn "portal:probe" "手前の NG が解消されていないためスキップしました"
  else
    if OUT="$(bash "$ROOT/scripts/attendance.sh" 2> /dev/null)" && echo "$OUT" | jq -e 'type == "array"' > /dev/null 2>&1; then
      ok "portal:probe" "出欠データを $(echo "$OUT" | jq 'length') 件取得できました"
    else
      ng "portal:probe" "有効な JSON が返りませんでした（PHPSESSID の期限切れ・URL/認証情報の誤りの可能性）"
    fi
  fi
fi

echo
if [ "$NG_COUNT" -eq 0 ]; then
  echo "RESULT ok  すべてのチェックを通過しました。"
  exit 0
else
  echo "RESULT ng  $NG_COUNT 件の NG があります。上記を解消してください。"
  exit 1
fi
