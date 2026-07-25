#!/bin/bash

# 欠席日を範囲指定で一覧表示する。
# attendance.sh で全欠席データを取得し、指定範囲で絞って日付ごとに整形表示する。
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
#     指定日の欠席コマ（時限・教科）だけを表示する。
#     一覧から日付を選んで公欠申請へ進むとき、どのコマが欠席なのかを確認する用途。
#
# 補足:
#   - 既に取得済みの JSON を使い回したい場合は環境変数 ABSENCE_JSON にパスを渡す
#     （その場合 attendance.sh の再取得をスキップする）。

set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"

# 範囲指定 → 基準日(YYYYMMDD) と 表示ラベル を求める
back() { date -v-"$1" +%Y%m%d 2>/dev/null || date -d "$2 ago" +%Y%m%d; }

MODE="list"
TARGET=""

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
if [ -n "${ABSENCE_JSON:-}" ]; then
  JSON="$ABSENCE_JSON"
else
  JSON="$(mktemp)"
  trap 'rm -f "$JSON"' EXIT
  bash "$DIR/attendance.sh" > "$JSON"
fi

if [ "$MODE" = "detail" ]; then
  jq -r --arg d "$TARGET" '[.[] | select(.d2_jugyou_date == $d)]
    | sort_by(.d2_jugyou_jigen | tostring | tonumber) | .[]
    | "\(.d2_jugyou_jigen)\t\(.ky_kyouka_name)"' "$JSON" \
  | python3 -c '
import sys, datetime
d = sys.argv[1]
w = ["月", "火", "水", "木", "金", "土", "日"]
rows = [l.rstrip("\n") for l in sys.stdin if l.strip()]
dt = datetime.date(int(d[:4]), int(d[4:6]), int(d[6:8]))
head = dt.isoformat() + " (" + w[dt.weekday()] + ")"
if not rows:
    print(head + " に欠席のコマはありません。")
    sys.exit(0)
print(head + " の欠席コマ（" + str(len(rows)) + "コマ）\n")
for r in rows:
    jigen, subj = r.split("\t")
    print("  " + str(jigen) + "限 … " + subj)
' "$TARGET"
  exit 0
fi

jq -r --arg cut "$CUT" '[.[] | select(.d2_jugyou_date >= $cut)]
  | group_by(.d2_jugyou_date) | sort_by(.[0].d2_jugyou_date) | reverse | .[]
  | "\(.[0].d2_jugyou_date)\t\(length)\t" + ([.[].ky_kyouka_name] | unique | join(", "))' "$JSON" \
| python3 -c '
import sys, datetime
label = sys.argv[1]
w = ["月", "火", "水", "木", "金", "土", "日"]
rows = [l.rstrip("\n") for l in sys.stdin if l.strip()]
coma = sum(int(r.split("\t")[1]) for r in rows)
print("欠席一覧（" + label + " / 全 " + str(coma) + " コマ・" + str(len(rows)) + " 日分）\n")
if not rows:
    print("  該当する欠席はありません。")
width = len(str(len(rows)))
for i, r in enumerate(rows, 1):
    d, n, subj = r.split("\t")
    dt = datetime.date(int(d[:4]), int(d[4:6]), int(d[6:8]))
    print("  " + str(i).rjust(width) + ") " + dt.isoformat() + " (" + w[dt.weekday()] + ") … " + subj + "（" + n + "コマ）")
' "$LABEL"
