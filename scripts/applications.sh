#!/bin/bash

# 学生ポータルの「申請一覧」から公欠届の申請データを取得して JSON 配列で出力する。
#
# 申請一覧ページ (student_application_list.html) が内部で叩いている
#   /PortalManagementWeb/public/studentapplicationlist/search
# は「申請番号・申請名・承認状態・承認日」しか返さず、どの日付の公欠届なのかが分からない。
# そのため、公欠届の各申請について詳細ページと同じ
#   /PortalManagementWeb/public/studentapplicationdetail/initview
# を叩き、申請された日付・コマ（ad_flex_item_value1〜10）を取得して突き合わせる。
#
# 詳細の取得はポータルで「詳細」を開くのと同じ呼び出しなので、承認通知の「未読」表示が
# 消える可能性がある。無駄に何度も叩かないよう、取得した詳細は logs/.applications_cache.json に
# キャッシュし、2回目以降は同じ申請を取りに行かない（承認状態は毎回一覧から取り直すので、
# キャッシュしていても「未承認 → 承認済」の変化はきちんと反映される）。
#
# 使い方:
#   scripts/applications.sh [SINCE_YYYYMMDD]
#     SINCE_YYYYMMDD  この日以降の欠席に関係しそうな申請だけを詳細取得する（省略時は全件）。
#                     申請は欠席日より前後するため、実際には SINCE の60日前まで遡って取得する。
#
# 出力（標準出力）:
#   [
#     {
#       "ad_sid": "331043",              申請番号
#       "status": "未承認",              承認状態（未承認 / 承認済 / 却下 / キャンセル）
#       "approved_date": "2026/09/07",   承認日（無ければ空文字）
#       "application_date": "20260913",  申請日
#       "reason": "...",                 申請理由
#       "items": [ { "date": "20260912", "period": "3限目/設計・開発/迫田先生" } ]
#     }
#   ]
#
# 終了コード:
#   0  取得成功
#   1  取得失敗（セッション切れ・認証失敗など）

set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$DIR/.." && pwd)"
CACHE="${ABSENCE_APPLICATIONS_CACHE:-$ROOT/logs/.applications_cache.json}"

# 公欠届の申請名（申請一覧の「申請名」列がこれと一致するものだけを対象にする）
APPLICATION_NAME="公欠届"

SINCE="${1:-}"
SINCE="${SINCE//-/}"

source "$ROOT/.env"

bash "$DIR/login.sh" \
  "$STUDENT_PORTAL_URL" "$STUDENT_PORTAL_USER_ID" "$STUDENT_PORTAL_PASSWORD" "$STUDENT_PORTAL_PHPSESSID" \
  > /dev/null

BASE="${STUDENT_PORTAL_URL}/PortalManagementWeb/public"
TMP=$(mktemp)
ROWS_FILE=$(mktemp)
OUT=$(mktemp)
trap 'rm -f "$TMP" "$ROWS_FILE" "$OUT"' EXIT

# --- 申請一覧を全ページ取得して「申請番号 / 申請名 / 承認状態 / 承認日」に整形 ---

ROWS=100
PAGE=1
: > "$ROWS_FILE"

while : ; do
  TS=$(date +%s%3N)
  curl -s "${BASE}/studentapplicationlist/search?lsc=OCA&initview=1&current_page=${PAGE}&rows_per_page=${ROWS}&ts=${TS}" \
    --cookie "PHPSESSID=${STUDENT_PORTAL_PHPSESSID}" -o "$TMP"

  if ! jq -e '.result_flg == true' "$TMP" > /dev/null 2>&1; then
    echo "エラー: 申請一覧を取得できませんでした（セッション切れ・認証失敗の可能性）。" >&2
    exit 1
  fi

  jq -r '.data.application_html // ""' "$TMP" | python3 -c '
import html, re, sys

source = sys.stdin.read()
for tr in re.findall(r"<tr[^>]*>(.*?)</tr>", source, re.S):
    cells = re.findall(r"<td[^>]*>(.*?)</td>", tr, re.S)
    if len(cells) < 4:
        continue
    def text(c):
        return html.unescape(re.sub(r"<[^>]+>", "", c)).replace(" ", " ").strip()
    number = re.match(r"\s*(\d+)", text(cells[0]))
    if not number:
        continue
    print("\t".join([number.group(1), text(cells[1]), text(cells[2]), text(cells[3])]))
' >> "$ROWS_FILE"

  COUNT=$(jq -r '.data.application_count // 0' "$TMP")
  GOT=$(wc -l < "$ROWS_FILE" | tr -d ' ')
  if [ "$GOT" -ge "$COUNT" ] || [ "$GOT" -eq 0 ]; then
    break
  fi
  PAGE=$((PAGE + 1))
done

# --- 詳細取得の打ち切り基準（SINCE の60日前より古い申請までは遡らない） ---

STOP="00000000"
if [ -n "$SINCE" ]; then
  Y="${SINCE:0:4}"; M="${SINCE:4:2}"; D="${SINCE:6:2}"
  STOP=$(date -j -v-60d -f %Y%m%d "$SINCE" +%Y%m%d 2>/dev/null \
      || date -d "${Y}-${M}-${D} -60 days" +%Y%m%d)
fi

[ -f "$CACHE" ] || { mkdir -p "$(dirname "$CACHE")"; echo "{}" > "$CACHE"; }
jq -e . "$CACHE" > /dev/null 2>&1 || echo "{}" > "$CACHE"

echo "[]" > "$OUT"
FETCHED=0

while IFS=$'\t' read -r SID NAME STATUS APPROVED_DATE; do
  [ -n "${SID:-}" ] || continue
  [ "$NAME" = "$APPLICATION_NAME" ] || continue

  DETAIL=$(jq -c --arg sid "$SID" '.[$sid] // empty' "$CACHE")

  if [ -z "$DETAIL" ]; then
    TS=$(date +%s%3N)
    if ! curl -s -X POST "${BASE}/studentapplicationdetail/initview?ts=${TS}" \
        --cookie "PHPSESSID=${STUDENT_PORTAL_PHPSESSID}" \
        -d "mode=1&ad_sid=${SID}" -o "$TMP" \
      || ! jq -e '.data.application_data != null' "$TMP" > /dev/null 2>&1; then
      echo "警告: 申請番号 ${SID} の詳細を取得できませんでした（スキップします）。" >&2
      continue
    fi

    DETAIL=$(jq -c '.data.application_data as $a
      | {
          application_date: ($a.ad_application_date // ""),
          reason: ($a.ad_application_remarks // ""),
          image: ($a.aaf_file_name // ""),
          items: ([range(0; 5) as $i
                   | { date: ($a["ad_flex_item_value\($i * 2 + 1)"] // ""),
                       period: ($a["ad_flex_item_value\($i * 2 + 2)"] // "") }]
                  | map(select(.date != "")))
        }' "$TMP")

    jq --arg sid "$SID" --argjson detail "$DETAIL" '.[$sid] = $detail' "$CACHE" > "${CACHE}.new" \
      && mv "${CACHE}.new" "$CACHE"
    FETCHED=$((FETCHED + 1))
  fi

  APP_DATE=$(printf '%s' "$DETAIL" | jq -r '.application_date // ""')

  jq -c --arg sid "$SID" --arg status "$STATUS" --arg approved "$APPROVED_DATE" --argjson detail "$DETAIL" \
    '. + [$detail + { ad_sid: $sid, status: $status, approved_date: $approved }]' "$OUT" > "${OUT}.new" \
    && mv "${OUT}.new" "$OUT"

  # 一覧は申請番号の新しい順なので、SINCE より十分古い申請まで来たらそこで打ち切る
  if [ -n "$APP_DATE" ] && [ "$APP_DATE" \< "$STOP" ]; then
    break
  fi
done < "$ROWS_FILE"

if [ "$FETCHED" -gt 0 ]; then
  echo "申請の詳細を ${FETCHED} 件取得しました。" >&2
fi

jq '.' "$OUT"
