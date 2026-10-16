#!/usr/bin/env python3
"""Check the minimum calendar-month interval without creating or changing any Release."""

import argparse
import calendar
from datetime import datetime, timezone
import json
from pathlib import Path
import sys


def parse_time(value):
    if not isinstance(value, str):
        raise ValueError("公开 Release 缺少有效的 published_at")
    result = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if result.tzinfo is None:
        raise ValueError("发布时间必须包含时区")
    return result.astimezone(timezone.utc)


def one_month_after(value):
    year, month = value.year + (value.month == 12), value.month % 12 + 1
    day = min(value.day, calendar.monthrange(year, month)[1])
    return value.replace(year=year, month=month, day=day)


def evaluate(data, now):
    if not isinstance(data, list):
        raise ValueError("Release API 响应必须是数组，不能将接口错误视为首次发布")
    if data and all(isinstance(page, list) for page in data):
        data = [release for page in data for release in page]
    published = []
    for release in data:
        if not isinstance(release, dict) or type(release.get("draft")) is not bool:
            raise ValueError("Release 记录格式无效")
        if release["draft"]:
            continue
        # Include pre-releases: publishing a preview must not bypass the monthly limit.
        published.append((parse_time(release.get("published_at")), release.get("tag_name", "")))
    if not published:
        return {"eligible": True, "lastRelease": None, "earliestReleaseAt": None, "reason": "尚无公开 Release，可进行首次发布"}
    last_date, last_tag = max(published, key=lambda item: item[0])
    earliest = one_month_after(last_date)
    eligible = now.astimezone(timezone.utc) >= earliest
    return {
        "eligible": eligible,
        "lastRelease": last_tag,
        "earliestReleaseAt": earliest.isoformat().replace("+00:00", "Z"),
        "reason": "已满一个自然月，可发布" if eligible else "距上次公开发布不足一个自然月，本次不发布 Release",
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--releases-json", required=True, type=Path)
    parser.add_argument("--now", help="UTC/带时区时间，仅用于复现检查")
    parser.add_argument("--github-output", type=Path)
    args = parser.parse_args()
    try:
        decision = evaluate(json.loads(args.releases_json.read_text()), parse_time(args.now) if args.now else datetime.now(timezone.utc))
    except (ValueError, OSError, TypeError) as error:
        print("无法核对发布间隔，禁止发布：" + str(error), file=sys.stderr)
        return 1
    print(json.dumps(decision, ensure_ascii=False, indent=2))
    if args.github_output:
        with args.github_output.open("a") as output:
            output.write("eligible=" + str(decision["eligible"]).lower() + "\n")
            output.write("earliest_release_at=" + (decision["earliestReleaseAt"] or "") + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
