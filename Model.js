// Pure presentation logic for the agenda widget: countdowns, urgency, and day
// grouping. Kept free of QML types so it can be unit-tested under node, and so
// the QML files stay declarative.

var WEEKDAYS = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]
var MONTHS = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN",
              "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]

// Urgency thresholds in minutes until start, mirroring the waybar module the
// widget replaces. The -2 floor keeps a meeting flashing for a couple of
// minutes after it starts, which is exactly when you are late for it.
var CRITICAL_FLOOR_MIN = -2
var CRITICAL_MIN = 2
var WARNING_MIN = 5
var SOON_MIN = 15

// The helper emits naive local ISO timestamps. Parse the parts explicitly
// rather than trusting the engine's ISO handling, which differs on whether a
// zoneless string means local time or UTC.
function parseIso(value) {
  var match = String(value || "").match(/^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::(\d{2}))?/)
  if (!match) return null
  return new Date(Number(match[1]), Number(match[2]) - 1, Number(match[3]),
                  Number(match[4]), Number(match[5]), Number(match[6] || 0))
}

function minutesUntil(startIso, nowMs) {
  var start = parseIso(startIso)
  if (!start) return null
  return Math.floor((start.getTime() - nowMs) / 60000)
}

function humanizeCountdown(startIso, nowMs) {
  var minutes = minutesUntil(startIso, nowMs)
  if (minutes === null) return ""
  if (minutes < 0) return "Now"
  if (minutes < 60) return "In " + minutes + " min"

  var hours = Math.floor(minutes / 60)
  var rest = minutes % 60
  return rest ? "In " + hours + "h " + rest + "m" : "In " + hours + "h"
}

// "live" is a meeting well underway; "critical" covers the window where you
// should already be moving.
function urgencyFor(startIso, nowMs) {
  var minutes = minutesUntil(startIso, nowMs)
  if (minutes === null) return "normal"
  if (minutes < CRITICAL_FLOOR_MIN) return "live"
  if (minutes <= CRITICAL_MIN) return "critical"
  if (minutes <= WARNING_MIN) return "warning"
  if (minutes <= SOON_MIN) return "soon"
  return "normal"
}

function truncate(text, length) {
  var value = String(text || "")
  if (value.length <= length) return value
  return value.substring(0, length - 1) + "…"
}

function barLabel(event, nowMs, maxTitle) {
  if (!event) return ""
  return humanizeCountdown(event.start, nowMs) + " - " + truncate(event.title, maxTitle)
}

function timeLabel(startIso) {
  var start = parseIso(startIso)
  if (!start) return ""
  return pad(start.getHours()) + ":" + pad(start.getMinutes())
}

function pad(value) {
  return value < 10 ? "0" + value : String(value)
}

function sameDay(a, b) {
  return a.getFullYear() === b.getFullYear()
    && a.getMonth() === b.getMonth()
    && a.getDate() === b.getDate()
}

function dayLabel(startIso, nowMs) {
  var start = parseIso(startIso)
  if (!start) return ""

  var today = new Date(nowMs)
  if (sameDay(start, today)) return "TODAY"

  var tomorrow = new Date(today.getFullYear(), today.getMonth(), today.getDate() + 1)
  if (sameDay(start, tomorrow)) return "TOMORROW"

  return WEEKDAYS[start.getDay()] + " " + start.getDate() + " " + MONTHS[start.getMonth()]
}

// Groups events into day buckets, in time order.
//
// The helper deliberately sorts meetings already underway to the end so the
// bar can count down to the next one you have to get to. The popup reads as a
// timeline instead, so it re-sorts chronologically — otherwise the meeting you
// are sitting in renders beneath the ones that follow it.
function groupByDay(events, nowMs) {
  var groups = []
  var byLabel = {}
  var list = (events || []).slice().sort(function(a, b) {
    return String(a.start).localeCompare(String(b.start))
  })

  for (var i = 0; i < list.length; i++) {
    var label = dayLabel(list[i].start, nowMs)
    if (!byLabel[label]) {
      byLabel[label] = { label: label, events: [] }
      groups.push(byLabel[label])
    }
    byLabel[label].events.push(list[i])
  }
  return groups
}

function summaryText(events, nowMs) {
  var today = new Date(nowMs)
  var count = 0
  var list = events || []

  for (var i = 0; i < list.length; i++) {
    var start = parseIso(list[i].start)
    if (start && sameDay(start, today)) count += 1
  }
  return count === 0 ? "Nothing left today" : count + " left today"
}

function parsePayload(raw) {
  var empty = { events: [], error: "" }
  try {
    var data = JSON.parse(String(raw || ""))
    if (!data || typeof data !== "object") return { events: [], error: "Unreadable agenda" }
    return {
      events: data.error ? [] : (data.events || []),
      error: data.error ? String(data.error) : ""
    }
  } catch (e) {
    return { events: [], error: "Unreadable agenda" }
  }
}
