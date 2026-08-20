import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// Polls the agenda helper and publishes the parsed result. Kept separate from
// Panel.qml so the rendering stays declarative and the process lifecycle has
// one owner.
Item {
  id: root

  property var settings: ({})

  property var events: []
  property string error: ""
  property bool loaded: false

  readonly property bool refreshing: agendaProcess.running
  readonly property var nextEvent: events.length > 0 ? events[0] : null

  // Resolved from this file's own location so renaming the plugin directory
  // cannot strand the helper.
  readonly property string pluginDir: String(Qt.resolvedUrl("."))
    .replace(/^file:\/\//, "")
    .replace(/\/$/, "")

  // Empty means "every calendar gcalcli knows about" — the helper omits the
  // --calendar flags entirely rather than substituting a name of its own.
  readonly property var calendars: {
    var configured = setting("calendars", null)
    return configured && configured.length > 0 ? configured : []
  }
  readonly property int intervalSec: intSetting("interval", 60, 15, 3600)
  readonly property int limit: intSetting("limit", 10, 1, 50)

  property string _output: ""

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, min, max) {
    var n = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(n)) n = fallback
    return Math.max(min, Math.min(max, n))
  }

  function refresh() {
    if (agendaProcess.running) return
    _output = ""

    var command = ["python3", pluginDir + "/scripts/agenda.py", "--limit", String(limit)]
    for (var i = 0; i < calendars.length; i++) command.push("--calendar", String(calendars[i]))

    agendaProcess.command = command
    agendaProcess.running = true
  }

  function apply(raw) {
    var parsed = Model.parsePayload(raw)
    root.events = parsed.events
    root.error = parsed.error
    root.loaded = true
  }

  Timer {
    interval: root.intervalSec * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Process {
    id: agendaProcess
    running: false
    stdout: StdioCollector { id: agendaStdout; waitForEnd: true; onStreamFinished: root._output = text }
    stderr: StdioCollector { id: agendaStderr; waitForEnd: true }

    onExited: function(exitCode) {
      var out = String(agendaStdout.text || root._output || "")
      if (exitCode === 0 && out !== "") {
        root.apply(out)
        return
      }
      // A helper that cannot run at all is still news worth showing, rather
      // than a widget that silently freezes on its last good agenda.
      root.events = []
      root.error = String(agendaStderr.text || "").trim().split("\n").pop() || "Agenda helper failed"
      root.loaded = true
    }
  }
}
