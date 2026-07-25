#!/bin/bash

# 学生ポータルの「出欠確認」から出欠データを取得して JSON 配列で出力する。
#
# 出欠確認ページ (attendance_detail.html) が内部で叩いている
#   /PortalManagementWeb/public/attendancedetail/search
# を直接叩くことで、HTMLをスクレイピングせず構造化データを取得する。
#
# 使い方:
#   scripts/attendance.sh [SYUKETSU_KU] [YEAR]
#     SYUKETSU_KU  出欠区分（1:出席 2:欠席 3:遅刻 4:早退 5:公欠 6:理欠）。省略時は 2(欠席)。
#     YEAR         年度フィルタ（例: 2026）。省略時は全年度。
#
# 出力:
#   attendance_data を全ページ結合した JSON 配列を標準出力へ。
#   各要素の主なフィールド:
#     d2_jugyou_date   授業日 (YYYYMMDD)
#     d2_jugyou_jigen  時限
#     d2_syuketsu_ku   出欠区分
#     ky_kyouka_name   教科名

set -euo pipefail

source "$(dirname "$0")/../.env"

SYUKETSU_KU="${1:-2}"
YEAR="${2:-}"

# セッションを更新（ログイン）
bash "$(dirname "$0")/login.sh" \
  "$STUDENT_PORTAL_URL" "$STUDENT_PORTAL_USER_ID" "$STUDENT_PORTAL_PASSWORD" "$STUDENT_PORTAL_PHPSESSID" \
  > /dev/null

ROWS=100
PAGE=1
TMP=$(mktemp)
ALL=$(mktemp)
echo "[]" > "$ALL"

trap 'rm -f "$TMP" "$ALL" "${ALL}.new"' EXIT

while : ; do
  TS=$(date +%s%3N)
  PARAM="search_select_d2_year=${YEAR}&search_text_jugyou_date=&search_select_syuketsu_ku=${SYUKETSU_KU}&lsc=OCA&initview=1&current_page=${PAGE}&rows_per_page=${ROWS}"
  curl -s "${STUDENT_PORTAL_URL}/PortalManagementWeb/public/attendancedetail/search?${PARAM}&ts=${TS}" \
    --cookie "PHPSESSID=${STUDENT_PORTAL_PHPSESSID}" -o "$TMP"

  if ! jq -e . "$TMP" > /dev/null 2>&1; then
    echo "エラー: ポータルから有効なJSONが返りませんでした（セッション切れ・認証失敗の可能性）。" >&2
    exit 1
  fi

  # このページの attendance_data を結合
  jq -s '.[0] + (.[1].data.attendance_data // [])' "$ALL" "$TMP" > "${ALL}.new" && mv "${ALL}.new" "$ALL"

  COUNT=$(jq -r '.data.attendance_data_count // 0' "$TMP")
  PAGE_ROWS=$(jq -r '.data.attendance_data | length' "$TMP")
  GOT=$(jq -r 'length' "$ALL")

  # 全件取得済み、またはこれ以上データが無ければ終了
  if [ "$GOT" -ge "$COUNT" ] || [ "$PAGE_ROWS" -eq 0 ]; then
    break
  fi
  PAGE=$((PAGE + 1))
done

jq '.' "$ALL"
