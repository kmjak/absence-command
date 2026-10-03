#!/bin/bash

# 欠席日を範囲指定で一覧表示する。
# attendance.sh で全欠席データを、applications.sh で公欠届の申請データを取得し、
# 指定範囲で絞って日付ごとに「ステータス付き」で整形表示する。
#
# ステータス:
#   ✅ 承認済    その日の欠席コマがすべて承認済み（一覧には出さない。--detail では表示する）
#   🕒 申請中    申請済みだが、まだ承認されていない（未承認）
#   🔸 一部申請  欠席コマの一部だけが申請されている
#   ❌ 却下      申請したが却下された
#   ⬜ 未申請    まだ申請していない（キャンセル済みの申請しかない場合もこれ）
#
# 使い方:
#   scripts/absence_list.sh [RANGE]
#     RANGE（省略時は fy）:
#       fy         今年度（4/1以降）※デフォルト
#       1y         直近1年
#       6m         直近6ヶ月
#       3m         直近3ヶ月
#       1m         直近1ヶ月
#       all        全期間
#       YYYYMMDD   指定日以降
#
#   scripts/absence_list.sh --detail <YYYY-MM-DD|YYYYMMDD>
#     指定日の欠席コマ（時限・教科）をコマ単位のステータス付きで表示する。
#     一覧から日付を選んで公欠申請へ進むとき、どのコマが欠席で、どのコマが申請済みかを
#     確認する用途（二重申請の防止）。
#
#   --no-status を付けると申請データを取りに行かず、ステータス無しで高速に一覧表示する。
#
# 補足:
#   - 既に取得済みの JSON を使い回したい場合は環境変数 ABSENCE_JSON（欠席データ）と
#     ABSENCE_APPLICATIONS（申請データ）にパスを渡す（その場合は再取得をスキップする）。
#   - 申請データの取得に失敗しても一覧表示そのものは続行し、末尾に警告を出す。

set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"

# 範囲指定 → 基準日(YYYYMMDD) と 表示ラベル を求める
back() { date -v-"$1" +%Y%m%d 2>/dev/null || date -d "$2 ago" +%Y%m%d; }

MODE="list"
TARGET=""
WITH_STATUS=1

ARGS=()
for arg in "$@"; do
  case "$arg" in
    --no-status) WITH_STATUS=0 ;;
    *)           ARGS+=("$arg") ;;
  esac
done
set -- ${ARGS+"${ARGS[@]}"}

if [ "${1:-}" = "--detail" ]; then
  MODE="detail"
  TARGET="${2:-}"
  if [ -z "$TARGET" ]; then
    echo "使い方: absence_list.sh --detail <YYYY-MM-DD|YYYYMMDD>" >&2
    exit 1
  fi
  TARGET="${TARGET//-/}"
  if ! [[ "$TARGET" =~ ^[0-9]{8}$ ]]; then
    echo "日付の形式が不正です: ${2}（YYYY-MM-DD または YYYYMMDD）" >&2
    exit 1
  fi
else
  RANGE="${1:-fy}"
  case "$RANGE" in
    all)         CUT="00000000"; LABEL="全期間" ;;
    fy)
      yy=$(date +%Y); mm=$((10#$(date +%m)))
      [ "$mm" -lt 4 ] && yy=$((yy - 1))
      CUT="${yy}0401"; LABEL="今年度（${yy}/04以降）" ;;
    1y)          CUT="$(back 1y '1 year')";   LABEL="直近1年" ;;
    6m)          CUT="$(back 6m '6 months')"; LABEL="直近6ヶ月" ;;
    3m)          CUT="$(back 3m '3 months')"; LABEL="直近3ヶ月" ;;
    1m)          CUT="$(back 1m '1 month')";  LABEL="直近1ヶ月" ;;
    [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9])
                 CUT="$RANGE"; LABEL="${RANGE:0:4}-${RANGE:4:2}-${RANGE:6:2} 以降" ;;
    *)
      echo "不明な範囲指定: $RANGE" >&2
      echo "指定できる範囲: fy / 1y / 6m / 3m / 1m / all / YYYYMMDD" >&2
      exit 1 ;;
  esac
fi

# 欠席データを用意（ABSENCE_JSON が渡されていればそれを使う）
JSON="${ABSENCE_JSON:-}"
APPS=""
APPS_TMP=""
WARNING=""

cleanup() { [ -n "${JSON_TMP:-}" ] && rm -f "$JSON_TMP"; [ -n "$APPS_TMP" ] && rm -f "$APPS_TMP"; return 0; }
trap cleanup EXIT

if [ -z "$JSON" ]; then
  JSON_TMP="$(mktemp)"
  JSON="$JSON_TMP"
  bash "$DIR/attendance.sh" > "$JSON"
fi

# 申請データを用意（取得に失敗してもステータス無しで一覧は出す）
if [ "$WITH_STATUS" = "1" ]; then
  if [ -n "${ABSENCE_APPLICATIONS:-}" ]; then
    APPS="$ABSENCE_APPLICATIONS"
  else
    APPS_TMP="$(mktemp)"
    SINCE="${CUT:-}"
    [ "$MODE" = "detail" ] && SINCE="$TARGET"
    if bash "$DIR/applications.sh" "$SINCE" > "$APPS_TMP"; then
      APPS="$APPS_TMP"
    else
      WARNING="申請ステータスを取得できませんでした（セッション切れの可能性。./scripts/session.sh で取り直せます）"
    fi
  fi
fi

if [ "$MODE" = "detail" ]; then
  python3 "$DIR/absence_status.py" detail "$JSON" "$APPS" "$TARGET" "$WARNING"
  exit 0
fi

python3 "$DIR/absence_status.py" list "$JSON" "$APPS" "$CUT" "$LABEL" "$WARNING"
