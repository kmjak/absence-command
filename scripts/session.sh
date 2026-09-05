#!/bin/bash

# 学生ポータルにログインして新しい PHPSESSID を取得し、.env に自動で書き込む。
#
# ポータルのログインAPI (/PortalManagementWeb/public/login/do) は、
# Cookie を付けずに POST すると `Set-Cookie: PHPSESSID=...` で新しいセッションを発行する。
# その値を取り出して .env の STUDENT_PORTAL_PHPSESSID に反映するため、
# ブラウザの開発者ツールから手動でコピーする必要がない。
#
# 使い方:
#   scripts/session.sh            新しい PHPSESSID を取得して .env を更新する
#   scripts/session.sh --print    取得した PHPSESSID を標準出力に出すだけ（.env は変更しない）
#   scripts/session.sh --no-verify 取得後の疎通確認を省略する
#
# 出力:
#   通常は結果メッセージのみ。PHPSESSID の値は --print のとき以外は表示しない。
#
# 終了コード:
#   0  取得（と書き込み）に成功
#   1  失敗（認証情報の誤り・ネットワークエラーなど）
#   2  .env の設定不足

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$ROOT/.env"

PRINT_ONLY=0
VERIFY=1
for arg in "$@"; do
  case "$arg" in
    --print)     PRINT_ONLY=1 ;;
    --no-verify) VERIFY=0 ;;
    *) echo "不明なオプション: $arg" >&2; exit 2 ;;
  esac
done

if [ ! -f "$ENV_FILE" ]; then
  echo "エラー: .env がありません（cp .env.example .env）" >&2
  exit 2
fi

# PHPSESSID はこれから取得する値なので、未設定でも読み込みが失敗しないようにする
STUDENT_PORTAL_URL=""
STUDENT_PORTAL_USER_ID=""
STUDENT_PORTAL_PASSWORD=""
# shellcheck disable=SC1090
source "$ENV_FILE"

for key in STUDENT_PORTAL_URL STUDENT_PORTAL_USER_ID STUDENT_PORTAL_PASSWORD; do
  if [ -z "${!key}" ]; then
    echo "エラー: .env の ${key} が未設定です。" >&2
    exit 2
  fi
done
case "$STUDENT_PORTAL_URL" in
  https://example.com) echo "エラー: .env の STUDENT_PORTAL_URL が雛形のままです。" >&2; exit 2 ;;
esac

HDR=$(mktemp)
trap 'rm -f "$HDR"' EXIT

TS=$(date +%s%3N)
# Cookie を付けずに POST することで、サーバに新しいセッションを発行させる
BODY=$(curl -s -D "$HDR" -X POST "${STUDENT_PORTAL_URL}/PortalManagementWeb/public/login/do?ts=${TS}" \
  -d "user_id=${STUDENT_PORTAL_USER_ID}&user_pass=${STUDENT_PORTAL_PASSWORD}&login_school_code=OCA")

if [ -z "$BODY" ]; then
  echo "エラー: ポータルから応答がありませんでした（STUDENT_PORTAL_URL とネットワークを確認してください）。" >&2
  exit 1
fi

if ! echo "$BODY" | jq -e '.result_flg == true' > /dev/null 2>&1; then
  echo "エラー: ログインに失敗しました（ログインID / パスワードを確認してください）。" >&2
  exit 1
fi

SESSION_ID=$(grep -i '^set-cookie:' "$HDR" | sed -nE 's/.*PHPSESSID=([^;[:space:]]+).*/\1/p' | head -1)
if [ -z "$SESSION_ID" ]; then
  echo "エラー: ログインには成功しましたが PHPSESSID を取得できませんでした。" >&2
  exit 1
fi

if [ "$VERIFY" = "1" ]; then
  TS=$(date +%s%3N)
  PARAM="search_select_d2_year=&search_text_jugyou_date=&search_select_syuketsu_ku=2&lsc=OCA&initview=1&current_page=1&rows_per_page=1"
  if ! curl -s "${STUDENT_PORTAL_URL}/PortalManagementWeb/public/attendancedetail/search?${PARAM}&ts=${TS}" \
      --cookie "PHPSESSID=${SESSION_ID}" | jq -e '.result_flg == true' > /dev/null 2>&1; then
    echo "エラー: 取得した PHPSESSID で出欠データを取得できませんでした。" >&2
    exit 1
  fi
fi

if [ "$PRINT_ONLY" = "1" ]; then
  echo "$SESSION_ID"
  exit 0
fi

# .env の該当行だけを差し替える（行が無ければ末尾に追記する）。
# 値は環境変数経由で awk に渡し、記号が混ざってもエスケープ事故が起きないようにする。
TMP_ENV=$(mktemp)
SESSION_ID="$SESSION_ID" awk '
  BEGIN { replaced = 0; value = ENVIRON["SESSION_ID"] }
  /^[[:space:]]*STUDENT_PORTAL_PHPSESSID[[:space:]]*=/ {
    if (!replaced) { print "STUDENT_PORTAL_PHPSESSID=" value; replaced = 1 }
    next
  }
  { print }
  END { if (!replaced) print "STUDENT_PORTAL_PHPSESSID=" value }
' "$ENV_FILE" > "$TMP_ENV" || { rm -f "$TMP_ENV"; echo "エラー: .env の更新に失敗しました。" >&2; exit 1; }

# 既存の .env のパーミッションを引き継ぐ（内容を入れ替えるだけで作り直さない）
cat "$TMP_ENV" > "$ENV_FILE"
rm -f "$TMP_ENV"

echo "PHPSESSID を取得して .env に設定しました。"
