// Model.js is QML JavaScript — no module system. Evaluate it in a sandbox and
// pull the functions out, so the production file needs no test-only exports.
const { test } = require("node:test")
const assert = require("node:assert")
const fs = require("node:fs")
const path = require("node:path")
const vm = require("node:vm")

const source = fs.readFileSync(path.join(__dirname, "..", "Model.js"), "utf8")
const Model = vm.createContext({})
vm.runInContext(source, Model)

const NOW = new Date("2026-08-20T10:00:00").getTime()
const at = (iso) => new Date(iso).getTime()

function event(startIso, endIso, extra = {}) {
  return Object.assign({
    title: "Standup",
    start: startIso,
    end: endIso,
    live: at(startIso) <= NOW,
    url: "https://meet.google.com/abc",
    meeting: true,
  }, extra)
}

test("countdown reads in minutes for the next hour", () => {
  assert.equal(Model.humanizeCountdown("2026-08-20T10:25:00", NOW), "In 25 min")
})

test("countdown reads in hours and minutes beyond an hour", () => {
  assert.equal(Model.humanizeCountdown("2026-08-20T12:35:00", NOW), "In 2h 35m")
})

test("countdown drops the minutes on a whole hour", () => {
  assert.equal(Model.humanizeCountdown("2026-08-20T13:00:00", NOW), "In 3h")
})

test("countdown for a meeting already underway reads Now", () => {
  assert.equal(Model.humanizeCountdown("2026-08-20T09:45:00", NOW), "Now")
})

test("a meeting two minutes out is critical", () => {
  assert.equal(Model.urgencyFor("2026-08-20T10:02:00", NOW), "critical")
})

test("a meeting that started a minute ago is still critical", () => {
  assert.equal(Model.urgencyFor("2026-08-20T09:59:00", NOW), "critical")
})

test("a meeting five minutes out is a warning", () => {
  assert.equal(Model.urgencyFor("2026-08-20T10:05:00", NOW), "warning")
})

test("a meeting fifteen minutes out is soon", () => {
  assert.equal(Model.urgencyFor("2026-08-20T10:15:00", NOW), "soon")
})

test("a meeting later today is unremarkable", () => {
  assert.equal(Model.urgencyFor("2026-08-20T14:00:00", NOW), "normal")
})

test("a meeting well underway is live rather than critical", () => {
  assert.equal(Model.urgencyFor("2026-08-20T09:30:00", NOW), "live")
})

test("long titles are truncated with an ellipsis", () => {
  assert.equal(Model.truncate("Alignment Engine, Inc. | 1:1 with Alumni", 25),
               "Alignment Engine, Inc. |…")
})

test("short titles are left alone", () => {
  assert.equal(Model.truncate("Standup", 25), "Standup")
})

test("the bar label pairs the countdown with the title", () => {
  assert.equal(Model.barLabel(event("2026-08-20T10:25:00", "2026-08-20T10:55:00"), NOW, 25),
               "In 25 min - Standup")
})

test("the bar label is empty when there is nothing coming up", () => {
  assert.equal(Model.barLabel(null, NOW, 25), "")
})

test("times are rendered as 24-hour clock times", () => {
  assert.equal(Model.timeLabel("2026-08-20T09:05:00"), "09:05")
})

test("today's events are grouped under Today", () => {
  const groups = Model.groupByDay([event("2026-08-20T11:00:00", "2026-08-20T11:30:00")], NOW)
  assert.equal(groups.length, 1)
  assert.equal(groups[0].label, "TODAY")
})

test("tomorrow's events are grouped under Tomorrow", () => {
  const groups = Model.groupByDay([event("2026-08-21T09:00:00", "2026-08-21T09:30:00")], NOW)
  assert.equal(groups[0].label, "TOMORROW")
})

test("further-out events are grouped under a weekday and date", () => {
  const groups = Model.groupByDay([event("2026-08-24T11:00:00", "2026-08-24T11:30:00")], NOW)
  assert.equal(groups[0].label, "MON 24 AUG")
})

test("grouping keeps day order and event order within a day", () => {
  const groups = Model.groupByDay([
    event("2026-08-20T11:00:00", "2026-08-20T11:30:00", { title: "Standup" }),
    event("2026-08-22T18:00:00", "2026-08-22T23:00:00", { title: "Dinner" }),
    event("2026-08-20T14:00:00", "2026-08-20T15:00:00", { title: "Review" }),
  ], NOW)
  assert.deepEqual(groups.map(g => g.label), ["TODAY", "SAT 22 AUG"])
  assert.deepEqual(groups[0].events.map(e => e.title), ["Standup", "Review"])
})

test("the summary counts what is left today", () => {
  assert.equal(Model.summaryText([
    event("2026-08-20T11:00:00", "2026-08-20T11:30:00"),
    event("2026-08-20T14:00:00", "2026-08-20T15:00:00"),
    event("2026-08-22T18:00:00", "2026-08-22T23:00:00"),
  ], NOW), "2 left today")
})

test("the summary uses the singular for a single remaining event", () => {
  assert.equal(Model.summaryText([event("2026-08-20T11:00:00", "2026-08-20T11:30:00")], NOW),
               "1 left today")
})

test("the summary says the day is clear when nothing remains today", () => {
  assert.equal(Model.summaryText([event("2026-08-22T18:00:00", "2026-08-22T23:00:00")], NOW),
               "Nothing left today")
})

test("parsing a payload yields its events", () => {
  const parsed = Model.parsePayload(JSON.stringify({
    events: [event("2026-08-20T11:00:00", "2026-08-20T11:30:00")], error: null }))
  assert.equal(parsed.events.length, 1)
  assert.equal(parsed.error, "")
})

test("parsing junk yields no events and an error", () => {
  const parsed = Model.parsePayload("not json at all")
  assert.deepEqual(parsed.events, [])
  assert.ok(parsed.error.length > 0)
})

test("a payload error is carried through", () => {
  const parsed = Model.parsePayload(JSON.stringify({ events: [], error: "gcalcli not found" }))
  assert.equal(parsed.error, "gcalcli not found")
})

test("a meeting already underway still renders in time order within its day", () => {
  // The helper sorts in-progress events last so the bar can count down to the
  // next one; the popup reads as a timeline and must not inherit that order.
  const groups = Model.groupByDay([
    event("2026-08-20T11:00:00", "2026-08-20T11:30:00", { title: "Standup" }),
    event("2026-08-20T14:00:00", "2026-08-20T15:00:00", { title: "Review" }),
    event("2026-08-20T09:30:00", "2026-08-20T10:10:00", { title: "In Progress" }),
  ], NOW)
  assert.deepEqual(groups[0].events.map(e => e.title), ["In Progress", "Standup", "Review"])
})

test("days stay in date order even when a live event arrives last", () => {
  const groups = Model.groupByDay([
    event("2026-08-22T18:00:00", "2026-08-22T23:00:00", { title: "Dinner" }),
    event("2026-08-20T09:30:00", "2026-08-20T10:10:00", { title: "In Progress" }),
  ], NOW)
  assert.deepEqual(groups.map(g => g.label), ["TODAY", "SAT 22 AUG"])
})
