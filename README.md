# Agenda

An Omarchy bar widget that counts down to your next meeting and opens a
keyboard-navigable agenda popup. Calendar data comes from
[gcalcli](https://github.com/insanum/gcalcli).

```
In 25 min - Standup          ← bar label, colored by how soon it is
```

## Interactions

| Input | Action |
|---|---|
| Left click | Open/close the agenda popup |
| Right click | Refresh now |
| Middle click | Open the next meeting's link |
| `j` / `k` / arrows | Move through the agenda |
| `Enter` | Open the highlighted meeting |
| `r` | Refresh |
| `Esc` | Close |

Rows marked 󰕧 have a Meet link; clicking any row opens its meeting link,
falling back to the Google Calendar event page.

## Urgency

The bar label is colored from the active theme's roles, so it tracks theme
changes rather than fixed values:

| Time to start | Color | |
|---|---|---|
| ≤ 2 min | `urgent` | pulses |
| ≤ 5 min | `accent` | |
| ≤ 15 min | `foreground` | |
| further out | dimmed foreground | |
| in progress | `foreground` | row shows `now` |

A meeting stays "critical" for two minutes after it starts — the window in
which you are late for it.

## Settings

Set these inline on the widget's `shell.json` entry:

```json
{ "id": "censey.agenda",
  "calendars": ["Merged Calendars", "censey@gmail.com"],
  "interval": 60,
  "maxTitle": 25,
  "limit": 10 }
```

| Key | Default | Meaning |
|---|---|---|
| `calendars` | `["Merged Calendars", "censey@gmail.com"]` | gcalcli calendar names |
| `interval` | `60` | Seconds between fetches (15–3600) |
| `maxTitle` | `25` | Characters before the bar label is elided |
| `limit` | `10` | Upcoming events fetched. Meetings already underway are always kept, on top of this |

Countdowns are recomputed locally every 10s, so "In 3 min" stays honest
between fetches.

## Requirements

`gcalcli` on `PATH` or in `~/.local/bin`, already authorized:

```bash
uv tool install 'gcalcli==4.5.1'
gcalcli list          # confirms the cached OAuth token still works
```

`~/.local/bin` is preferred over `PATH` deliberately: a stale virtualenv can
leave a `gcalcli` shim whose interpreter no longer exists, and that shim would
otherwise shadow the working install.

## Layout

| File | Role |
|---|---|
| `Panel.qml` | Bar label and agenda popup |
| `Service.qml` | Polls the helper, publishes parsed results |
| `Model.js` | Countdown, urgency, and day grouping — no QML dependencies |
| `scripts/agenda.py` | gcalcli → JSON |

## Tests

```bash
python3 -m unittest discover -s tests   # helper
node --test tests/model.test.js         # presentation logic
```

## Gotchas

- Editing `Model.js` alone may not take effect: QML caches imported JS. Run
  `omarchy restart shell` if a change to it seems ignored.
- Stale widget instances from earlier hot-reloads keep the IPC target
  registered (`omarchy-shell censey.agenda …` reaches the old one). Restart the
  shell when IPC results look stale.
- All-day events are skipped; they are not meetings you can be late for.
