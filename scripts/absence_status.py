#!/usr/bin/env python3
"""欠席データと公欠届の申請データを突き合わせて一覧／詳細を整形表示する。

absence_list.sh から呼ばれる。単体で使うことは想定していない。

使い方:
    absence_status.py list   <欠席JSON> <申請JSON|""> <基準日YYYYMMDD> <範囲ラベル> [警告文]
    absence_status.py detail <欠席JSON> <申請JSON|""> <対象日YYYYMMDD>              [警告文]

申請JSON が空文字（ステータス取得をスキップ／失敗）の場合は、ステータス列を出さずに
従来どおりの一覧を表示し、警告文があれば末尾に添える。
"""

import datetime
import json
import re
import sys
import unicodedata

WEEKDAYS = ["月", "火", "水", "木", "金", "土", "日"]

# ポータルの承認状態 → 表示（アイコン, ラベル）
APPROVED = ("✅", "承認済")
PENDING = ("🕒", "申請中")
PARTIAL = ("🔸", "一部申請")
REJECTED = ("❌", "却下")
NONE = ("⬜", "未申請")

# 一覧のステータス内訳に出す順番（承認済の日は一覧に出さないので含めない）
SUMMARY_ORDER = [NONE, PENDING, PARTIAL, REJECTED]


def width(text):
    """全角を2文字ぶんとして数えた表示幅。

    Ⅱ / Ⅲ のような曖昧幅(A)の文字は、日本語環境の端末に合わせて全角として数える
    （教科名に「システム開発Ⅱ」などが含まれるため）。
    """
    return sum(2 if unicodedata.east_asian_width(c) in "WFA" else 1 for c in text)


def pad(text, size):
    return text + " " * max(0, size - width(text))


def format_date(yyyymmdd):
    d = datetime.date(int(yyyymmdd[:4]), int(yyyymmdd[4:6]), int(yyyymmdd[6:8]))
    return d.isoformat() + " (" + WEEKDAYS[d.weekday()] + ")"


def jigen_of(period):
    """「3限目/設計・開発/迫田先生」→ 3。数字が読めなければ None。"""
    m = re.match(r"\s*(\d+)", period or "")
    return int(m.group(1)) if m else None


def load_absences(path, keep):
    """欠席JSON → {日付: {時限: 教科名}}。keep(日付) が True のものだけ残す。"""
    with open(path, encoding="utf-8") as f:
        records = json.load(f)
    days = {}
    for r in records:
        date = r.get("d2_jugyou_date", "")
        if not date or not keep(date):
            continue
        jigen = jigen_of(r.get("d2_jugyou_jigen", ""))
        if jigen is None:
            continue
        days.setdefault(date, {})[jigen] = r.get("ky_kyouka_name", "")
    return days


def load_applications(path):
    """申請JSON → {日付: [{status, sid, jigens(None=全コマ扱い)}]}。"""
    if not path:
        return None
    with open(path, encoding="utf-8") as f:
        applications = json.load(f)

    by_date = {}
    for app in applications:
        grouped = {}
        for item in app.get("items", []):
            date = item.get("date", "")
            if not date:
                continue
            jigen = jigen_of(item.get("period", ""))
            # 時限が読み取れない申請は「その日の全コマ」を申請したものとして扱う
            if jigen is None:
                grouped[date] = None
            elif date not in grouped:
                grouped[date] = {jigen}
            elif grouped[date] is not None:
                grouped[date].add(jigen)

        for date, jigens in grouped.items():
            by_date.setdefault(date, []).append(
                {"status": app.get("status", ""), "sid": app.get("ad_sid", ""), "jigens": jigens}
            )
    return by_date


def coverage(absent_jigens, applications):
    """その日の申請を承認状態ごとに「どの時限をカバーしているか」へ畳み込む。"""
    covered = {"承認済": set(), "未承認": set(), "却下": set()}
    for app in applications:
        bucket = covered.get(app["status"])
        if bucket is None:  # キャンセル済みの申請は無かったものとして扱う
            continue
        bucket.update(absent_jigens if app["jigens"] is None else app["jigens"])
    return covered


def day_status(absent_jigens, applications):
    """その日のステータスを ((アイコン, ラベル), 補足) で返す。"""
    absent = set(absent_jigens)
    covered = coverage(absent, applications)
    approved = covered["承認済"] & absent
    pending = covered["未承認"] & absent
    rejected = covered["却下"] & absent
    applied = approved | pending

    if not applied:
        if rejected:
            return REJECTED, ""
        return NONE, ""
    if applied != absent:
        return PARTIAL, "うち{}コマ申請済み".format(len(applied))
    if pending:
        return PENDING, ""
    return APPROVED, ""


def jigen_status(jigen, applications):
    """コマ単位のステータスを ((アイコン, ラベル), 申請番号) で返す。"""
    for status, display in (("承認済", APPROVED), ("未承認", PENDING), ("却下", REJECTED)):
        for app in applications:
            if app["status"] == status and (app["jigens"] is None or jigen in app["jigens"]):
                return display, app["sid"]
    return NONE, ""


def print_list(days, apps_by_date, label, warning):
    dates = sorted(days, reverse=True)
    rows = []
    hidden = 0
    for date in dates:
        subjects = sorted(set(days[date].values()))
        if apps_by_date is None:
            rows.append((date, None, "", subjects, len(days[date])))
            continue
        display, note = day_status(days[date], apps_by_date.get(date, []))
        # 承認済みの日はもう対応不要なので一覧に出さない
        if display == APPROVED:
            hidden += 1
            continue
        rows.append((date, display, note, subjects, len(days[date])))

    total_koma = sum(koma for _, _, _, _, koma in rows)
    print(
        "欠席一覧（{} / 全 {} コマ・{} 日分{}）".format(
            label, total_koma, len(rows), "・承認済 {}日は非表示".format(hidden) if hidden else ""
        )
    )

    if apps_by_date is not None and rows:
        counts = {}
        for _, display, _, _, _ in rows:
            counts[display] = counts.get(display, 0) + 1
        breakdown = [
            "{} {} {}日".format(icon, name, counts[(icon, name)])
            for icon, name in SUMMARY_ORDER
            if counts.get((icon, name))
        ]
        print("内訳: " + " ・ ".join(breakdown))

    print("")
    if not rows:
        print("  該当する欠席はありません。")
    else:
        index_width = len(str(len(rows)))
        status_width = max(width(d[1][0] + " " + d[1][1]) for d in rows) if apps_by_date is not None else 0
        for i, (date, display, note, subjects, koma) in enumerate(rows, 1):
            status = ""
            if display is not None:
                status = pad(display[0] + " " + display[1], status_width) + "  "
            suffix = "（{}コマ{}）".format(koma, "・" + note if note else "")
            print(
                "  {}) {}{} … {}{}".format(
                    str(i).rjust(index_width), status, format_date(date), ", ".join(subjects), suffix
                )
            )

    if warning:
        print("")
        print("  ※ " + warning)


def print_detail(days, apps_by_date, target, warning):
    head = format_date(target)
    jigens = days.get(target, {})
    if not jigens:
        print(head + " に欠席のコマはありません。")
        return

    applications = apps_by_date.get(target, []) if apps_by_date is not None else []
    print("{} の欠席コマ（{}コマ）".format(head, len(jigens)))
    if apps_by_date is not None:
        display, note = day_status(jigens, applications)
        print("この日のステータス: {} {}{}".format(display[0], display[1], "（" + note + "）" if note else ""))
    print("")

    subject_width = max(width(name) for name in jigens.values())
    for jigen in sorted(jigens):
        line = "  {}限 … {}".format(jigen, pad(jigens[jigen], subject_width))
        if apps_by_date is not None:
            display, sid = jigen_status(jigen, applications)
            line += "  {} {}".format(display[0], display[1])
            if sid:
                line += "（申請番号 {}）".format(sid)
        print(line.rstrip())

    if warning:
        print("")
        print("  ※ " + warning)


def main():
    mode = sys.argv[1]
    absence_json = sys.argv[2]
    applications_json = sys.argv[3]

    apps_by_date = load_applications(applications_json)

    if mode == "detail":
        target = sys.argv[4]
        warning = sys.argv[5] if len(sys.argv) > 5 else ""
        days = load_absences(absence_json, lambda d: d == target)
        print_detail(days, apps_by_date, target, warning)
    else:
        cut = sys.argv[4]
        label = sys.argv[5]
        warning = sys.argv[6] if len(sys.argv) > 6 else ""
        days = load_absences(absence_json, lambda d: d >= cut)
        print_list(days, apps_by_date, label, warning)


if __name__ == "__main__":
    main()
