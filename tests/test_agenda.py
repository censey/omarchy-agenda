"""Tests for the gcalcli TSV -> JSON agenda helper."""

import importlib.util
import json
import unittest
from datetime import datetime
from pathlib import Path

HELPER = Path(__file__).resolve().parent.parent / "scripts" / "agenda.py"
spec = importlib.util.spec_from_file_location("agenda", HELPER)
agenda = importlib.util.module_from_spec(spec)
spec.loader.exec_module(agenda)

HEADER = "start_date\tstart_time\tend_date\tend_time\thtml_link\thangout_link\tconference_entry_point_type\tconference_uri\ttitle"
NOW = datetime(2026, 8, 20, 10, 0)


def row(start_date, start_time, end_date, end_time, title,
        html_link="", hangout_link="", entry_type="", conference_uri=""):
    return "\t".join([start_date, start_time, end_date, end_time,
                      html_link, hangout_link, entry_type, conference_uri, title])


class ParseEventsTest(unittest.TestCase):
    def test_skips_the_gcalcli_header_row(self):
        tsv = "\n".join([HEADER, row("2026-08-20", "11:00", "2026-08-20", "11:30", "Standup")])
        events = agenda.parse_events(tsv, now=NOW)
        self.assertEqual([e["title"] for e in events], ["Standup"])

    def test_skips_all_day_events_which_have_no_start_time(self):
        tsv = "\n".join([
            HEADER,
            row("2026-08-20", "", "2026-08-20", "", "Company Holiday"),
            row("2026-08-20", "11:00", "2026-08-20", "11:30", "Standup"),
        ])
        events = agenda.parse_events(tsv, now=NOW)
        self.assertEqual([e["title"] for e in events], ["Standup"])

    def test_skips_events_that_already_ended(self):
        tsv = "\n".join([
            HEADER,
            row("2026-08-20", "08:00", "2026-08-20", "09:00", "Early Bird"),
            row("2026-08-20", "11:00", "2026-08-20", "11:30", "Standup"),
        ])
        events = agenda.parse_events(tsv, now=NOW)
        self.assertEqual([e["title"] for e in events], ["Standup"])

    def test_orders_upcoming_ascending_then_in_progress_most_recent_first(self):
        tsv = "\n".join([
            HEADER,
            row("2026-08-20", "09:00", "2026-08-20", "12:00", "Long Workshop"),
            row("2026-08-20", "14:00", "2026-08-20", "15:00", "Later"),
            row("2026-08-20", "09:45", "2026-08-20", "10:30", "Just Started"),
            row("2026-08-20", "11:00", "2026-08-20", "11:30", "Standup"),
        ])
        events = agenda.parse_events(tsv, now=NOW)
        self.assertEqual([e["title"] for e in events],
                         ["Standup", "Later", "Just Started", "Long Workshop"])

    def test_limits_the_number_of_events_returned(self):
        rows = [row("2026-08-20", "11:%02d" % i, "2026-08-20", "23:00", "Event %d" % i)
                for i in range(12)]
        events = agenda.parse_events("\n".join([HEADER] + rows), now=NOW, limit=10)
        self.assertEqual(len(events), 10)

    def test_keeps_a_meeting_in_progress_even_when_the_limit_is_full(self):
        """The meeting you are sitting in is the one you most need listed, but
        it sorts last, so a naive limit drops it first."""
        rows = [row("2026-08-20", "1%d:00" % (i % 10), "2026-08-21", "23:00", "Upcoming %d" % i)
                for i in range(1, 12)]
        rows.append(row("2026-08-20", "09:30", "2026-08-20", "10:10", "In Progress"))
        events = agenda.parse_events("\n".join([HEADER] + rows), now=NOW, limit=10)
        self.assertIn("In Progress", [e["title"] for e in events])

    def test_the_limit_still_bounds_the_upcoming_events(self):
        rows = [row("2026-08-20", "1%d:00" % (i % 10), "2026-08-21", "23:00", "Upcoming %d" % i)
                for i in range(1, 12)]
        rows.append(row("2026-08-20", "09:30", "2026-08-20", "10:10", "In Progress"))
        events = agenda.parse_events("\n".join([HEADER] + rows), now=NOW, limit=10)
        upcoming = [e for e in events if not e["live"]]
        self.assertEqual(len(upcoming), 10)

    def test_prefers_the_hangout_link_over_the_calendar_link(self):
        tsv = "\n".join([HEADER, row("2026-08-20", "11:00", "2026-08-20", "11:30", "Standup",
                                     html_link="https://calendar/event", hangout_link="https://meet.google.com/abc")])
        self.assertEqual(agenda.parse_events(tsv, now=NOW)[0]["url"], "https://meet.google.com/abc")

    def test_falls_back_to_the_calendar_link_when_there_is_no_meeting_link(self):
        tsv = "\n".join([HEADER, row("2026-08-20", "11:00", "2026-08-20", "11:30", "Haircut",
                                     html_link="https://calendar/event")])
        self.assertEqual(agenda.parse_events(tsv, now=NOW)[0]["url"], "https://calendar/event")

    def test_emits_iso_timestamps_so_the_widget_can_recompute_countdowns(self):
        tsv = "\n".join([HEADER, row("2026-08-20", "11:00", "2026-08-20", "11:30", "Standup")])
        event = agenda.parse_events(tsv, now=NOW)[0]
        self.assertEqual(event["start"], "2026-08-20T11:00:00")
        self.assertEqual(event["end"], "2026-08-20T11:30:00")

    def test_marks_an_event_already_underway_as_live(self):
        tsv = "\n".join([
            HEADER,
            row("2026-08-20", "09:45", "2026-08-20", "10:30", "In Progress"),
            row("2026-08-20", "11:00", "2026-08-20", "11:30", "Standup"),
        ])
        by_title = {e["title"]: e for e in agenda.parse_events(tsv, now=NOW)}
        self.assertTrue(by_title["In Progress"]["live"])
        self.assertFalse(by_title["Standup"]["live"])

    def test_keeps_multi_day_events_from_the_rolling_agenda_window(self):
        tsv = "\n".join([
            HEADER,
            row("2026-08-20", "11:00", "2026-08-20", "11:30", "Standup"),
            row("2026-08-22", "18:00", "2026-08-22", "23:00", "Dinner"),
        ])
        self.assertEqual([e["title"] for e in agenda.parse_events(tsv, now=NOW)],
                         ["Standup", "Dinner"])

    def test_tolerates_short_and_blank_lines(self):
        tsv = "\n".join([HEADER, "", "2026-08-20\t11:00", "   ",
                         row("2026-08-20", "11:00", "2026-08-20", "11:30", "Standup")])
        self.assertEqual([e["title"] for e in agenda.parse_events(tsv, now=NOW)], ["Standup"])


class FindGcalcliTest(unittest.TestCase):
    """A stale gcalcli shim on PATH (a dead venv, say) must not win over the
    real one in ~/.local/bin."""

    def setUp(self):
        import os
        import tempfile
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        root = Path(self.tmp.name)

        self.home = root / "home"
        (self.home / ".local" / "bin").mkdir(parents=True)
        self.local_gcalcli = self.home / ".local" / "bin" / "gcalcli"
        self.local_gcalcli.write_text("#!/bin/sh\n")
        self.local_gcalcli.chmod(0o755)

        self.other = root / "venv" / "bin"
        self.other.mkdir(parents=True)
        stale = self.other / "gcalcli"
        stale.write_text("#!/bin/sh\n")
        stale.chmod(0o755)

        self.saved = dict(os.environ)
        self.addCleanup(lambda: (os.environ.clear(), os.environ.update(self.saved)))
        os.environ["HOME"] = str(self.home)
        os.environ["PATH"] = str(self.other)

    def test_prefers_local_bin_over_whatever_is_first_on_path(self):
        self.assertEqual(agenda.find_gcalcli(), str(self.local_gcalcli))

    def test_falls_back_to_path_when_local_bin_has_none(self):
        self.local_gcalcli.unlink()
        self.assertEqual(agenda.find_gcalcli(), str(self.other / "gcalcli"))


class BuildPayloadTest(unittest.TestCase):
    def test_reports_an_empty_agenda_without_failing(self):
        payload = agenda.build_payload("", now=NOW)
        self.assertEqual(payload["events"], [])
        self.assertIsNone(payload["error"])

    def test_payload_is_json_serializable(self):
        tsv = "\n".join([HEADER, row("2026-08-20", "11:00", "2026-08-20", "11:30", "Standup")])
        json.dumps(agenda.build_payload(tsv, now=NOW))


if __name__ == "__main__":
    unittest.main()
