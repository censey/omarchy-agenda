#!/usr/bin/env python3
"""Emit the upcoming agenda as JSON for the censey.agenda bar widget.

gcalcli owns the Google Calendar conversation; this script owns turning its
TSV into the shape Service.qml polls. Timestamps go out in ISO form and
countdowns are left to the widget, so "In 3 min" stays honest between the
60s polls rather than aging on screen.
"""

import argparse
import json
import os
import shutil
import subprocess
import sys
from datetime import datetime

DEFAULT_CALENDARS = ["Merged Calendars", "censey@gmail.com"]
DEFAULT_LIMIT = 10

# gcalcli --tsv prints a header row naming its columns. We read the layout
# from that row rather than trusting positions, because the column set shifts
# with the --details flags. These are the positions for our flag set, used
# only if the header is missing.
FALLBACK_COLUMNS = {
    "start_date": 0,
    "start_time": 1,
    "end_date": 2,
    "end_time": 3,
    "html_link": 4,
    "hangout_link": 5,
    "conference_uri": 7,
}


def _is_header(fields):
    return fields[0] == "start_date"


def _columns(fields):
    return {name: index for index, name in enumerate(fields)}


def _field(fields, columns, name, default=""):
    index = columns.get(name)
    if index is None or index >= len(fields):
        return default
    return fields[index]


def parse_events(output, now=None, limit=DEFAULT_LIMIT):
    """Parse gcalcli TSV into a list of timed, not-yet-finished events."""
    now = now or datetime.now()
    columns = dict(FALLBACK_COLUMNS)
    events = []

    for line in str(output or "").split("\n"):
        if not line.strip():
            continue
        fields = line.split("\t")
        if len(fields) < 4:
            continue
        if _is_header(fields):
            columns = _columns(fields)
            continue

        start_date = _field(fields, columns, "start_date")
        start_time = _field(fields, columns, "start_time")
        end_date = _field(fields, columns, "end_date")
        end_time = _field(fields, columns, "end_time")

        # All-day events carry no start time. They are not meetings you can
        # be late for, so the bar stays quiet about them.
        if not start_time:
            continue

        try:
            start = datetime.strptime(f"{start_date} {start_time}", "%Y-%m-%d %H:%M")
            end = datetime.strptime(f"{end_date} {end_time}", "%Y-%m-%d %H:%M")
        except ValueError:
            continue

        if end < now:
            continue

        # The title is whatever trails the known columns; gcalcli puts it last
        # regardless of which --details flags are in play.
        title = fields[-1].strip() or "No title"
        hangout = _field(fields, columns, "hangout_link")
        conference = _field(fields, columns, "conference_uri")
        html_link = _field(fields, columns, "html_link")

        events.append({
            "title": title,
            "start": start.isoformat(),
            "end": end.isoformat(),
            "live": start <= now,
            "url": hangout or conference or html_link,
            "meeting": bool(hangout or conference),
        })

    # Next thing you need to be at comes first. Meetings already underway sit
    # below the upcoming ones, newest first — the one you most likely just
    # joined is the one worth showing.
    upcoming = [e for e in events if not e["live"]]
    live = [e for e in events if e["live"]]
    upcoming.sort(key=lambda e: e["start"])
    live.sort(key=lambda e: e["start"], reverse=True)

    # The limit bounds how far ahead we look, not what is happening right now:
    # a meeting already underway is the one most worth listing, and it sorts
    # last, so applying the limit to the combined list would drop it first.
    return upcoming[:limit] + live


def build_payload(output, now=None, limit=DEFAULT_LIMIT, error=None):
    now = now or datetime.now()
    return {
        "events": [] if error else parse_events(output, now=now, limit=limit),
        "error": error,
        "generated": now.isoformat(),
    }


def find_gcalcli():
    """Locate gcalcli, preferring ~/.local/bin.

    PATH is searched second on purpose: an abandoned virtualenv can leave a
    gcalcli shim pointing at an interpreter that no longer exists, and that
    shim would otherwise shadow the working install.
    """
    local = os.path.join(os.path.expanduser("~"), ".local", "bin", "gcalcli")
    if os.path.isfile(local) and os.access(local, os.X_OK):
        return local
    return shutil.which("gcalcli")


def fetch(calendars, timeout=45):
    binary = find_gcalcli()
    if not binary:
        return None, "gcalcli not found"

    command = [binary, "--nocolor"]
    for calendar in calendars:
        command += ["--calendar", calendar]
    command += ["agenda", "today", "--nodeclined", "--details=end",
                "--details=url", "--details=conference", "--tsv"]

    try:
        result = subprocess.run(command, capture_output=True, text=True,
                                check=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return None, "gcalcli timed out"
    except subprocess.CalledProcessError as exc:
        detail = (exc.stderr or exc.stdout or "").strip().split("\n")
        return None, detail[-1][:120] if detail and detail[-1] else "gcalcli failed"
    except OSError as exc:
        return None, str(exc)[:120]

    return result.stdout, None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--calendar", action="append", dest="calendars",
                        help="calendar name; repeatable (default: %s)" % ", ".join(DEFAULT_CALENDARS))
    parser.add_argument("--limit", type=int, default=DEFAULT_LIMIT)
    args = parser.parse_args()

    output, error = fetch(args.calendars or DEFAULT_CALENDARS)
    payload = build_payload(output, limit=max(1, args.limit), error=error)
    json.dump(payload, sys.stdout, ensure_ascii=False)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
