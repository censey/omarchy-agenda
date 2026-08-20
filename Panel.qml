import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Bar label counting down to your next meeting, plus an agenda popup.
//
// Colors come from the theme roles rather than fixed values, so the urgency
// ladder reads correctly in every theme: accent for "soon-ish", urgent for
// "you are late", dimmed foreground for anything far enough out to ignore.
Panel {
  id: root
  moduleName: "censey.agenda"
  ipcTarget: "censey.agenda"
  manageIpc: false

  // Countdowns are recomputed locally on a short tick so "In 3 min" stays
  // truthful between the helper's much slower polls.
  property double nowMs: Date.now()
  property int cursorIndex: 0
  property bool cursorActive: false

  readonly property int maxTitle: intSetting("maxTitle", 25, 8, 80)

  // Ui/Panel does not carry the bar geometry helpers that Ui/BarWidget does,
  // so lift the one this widget needs off the host directly.
  readonly property bool vertical: bar ? bar.vertical : false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color accent: Color.accent
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.45)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property var nextEvent: agenda.nextEvent
  readonly property string urgency: nextEvent ? Model.urgencyFor(nextEvent.start, nowMs) : "normal"
  readonly property string label: Model.barLabel(nextEvent, nowMs, maxTitle)
  readonly property var groups: Model.groupByDay(agenda.events, nowMs)
  readonly property string summary: agenda.error !== "" ? "Agenda unavailable" : Model.summaryText(agenda.events, nowMs)

  // The urgency ladder, expressed in theme roles.
  readonly property color labelColor: {
    if (agenda.error !== "") return urgent
    switch (urgency) {
      case "critical": return urgent
      case "warning": return accent
      case "soon": return foreground
      case "live": return foreground
      default: return dim
    }
  }

  // Full title and time, since the bar label is truncated. The popup is the
  // detail view, so this stays to one line.
  readonly property string tooltip: {
    if (agenda.error !== "") return agenda.error
    if (!nextEvent) return "No upcoming meetings"
    return Model.timeLabel(nextEvent.start) + "  " + nextEvent.title
  }

  function intSetting(name, fallback, min, max) {
    var n = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(n)) n = fallback
    return Math.max(min, Math.min(max, n))
  }

  function refresh() {
    nowMs = Date.now()
    agenda.refresh()
  }

  function openEvent(event) {
    if (!event || !event.url || !bar) return
    bar.run("xdg-open " + bar.shellQuote(event.url))
    close()
  }

  function openNext() {
    openEvent(agenda.nextEvent)
  }

  // ---- Cursor, shared by keyboard and mouse. Rows render off `cursorIndex`,
  //      never off their own hover state, so exactly one row highlights.
  function flatEvents() {
    var flat = []
    for (var i = 0; i < groups.length; i++)
      for (var j = 0; j < groups[i].events.length; j++) flat.push(groups[i].events[j])
    return flat
  }

  function moveCursor(dx, dy) {
    cursorActive = true
    if (dy === 0) return
    var count = flatEvents().length
    if (count === 0) return
    cursorIndex = Math.max(0, Math.min(count - 1, cursorIndex + dy))
  }

  function activateCursor() {
    var flat = flatEvents()
    if (cursorIndex >= 0 && cursorIndex < flat.length) openEvent(flat[cursorIndex])
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    cursorActive = false
    cursorIndex = 0
    refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  Service {
    id: agenda
    settings: root.settings
  }

  Timer {
    interval: 10000
    running: true
    repeat: true
    onTriggered: root.nowMs = Date.now()
  }

  // Mirrors the flashing the waybar module used for an imminent meeting, but
  // driven by the same urgency state everything else reads.
  //
  // The pulse animates this root rather than the button: WidgetButton binds
  // its own `opacity` (for its dimmed/concealed states), and an animation
  // writing that property would replace the binding for good.
  SequentialAnimation {
    running: root.urgency === "critical"
    loops: Animation.Infinite
    alwaysRunToEnd: true

    NumberAnimation { target: root; property: "opacity"; from: 1.0; to: 0.35; duration: 500; easing.type: Easing.InOutQuad }
    NumberAnimation { target: root; property: "opacity"; from: 0.35; to: 1.0; duration: 500; easing.type: Easing.InOutQuad }

    onStopped: root.opacity = 1.0
  }

  IpcHandler {
    target: root.ipcTarget

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.broadcastRefresh(); return "ok" }
    function next(): string { return root.nextEvent ? root.label : "No upcoming meetings" }
  }

  function broadcastRefresh() {
    var items = bar && typeof bar.moduleWidgets === "function" ? bar.moduleWidgets(moduleName) : [root]
    for (var i = 0; i < items.length; i++) if (items[i] && items[i].refresh) items[i].refresh()
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // The glyph stands in when there is nothing to count down to, so the
    // agenda stays reachable on a clear day.
    text: root.vertical ? "󰃭" : (root.label !== "" ? root.label : "󰃭")
    fontSize: root.vertical || root.label === "" ? Style.bar.iconFont : Style.font.body
    foreground: root.labelColor
    tooltipText: root.opened ? "" : root.tooltip
    horizontalMargin: 8.5

    onPressed: function(b) {
      if (b === Qt.RightButton) root.refresh()
      else if (b === Qt.MiddleButton) root.openNext()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.moveCursor(dx, dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) { if (t === "r" || t === "R") root.refresh() }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          PanelHero {
            width: parent.width
            title: "Agenda"
            meta: root.summary
            foreground: root.foreground
            fontFamily: root.fontFamily

            iconComponent: Component {
              Text {
                text: "󰃭"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }
          }

          Text {
            visible: agenda.error !== ""
            width: parent.width
            text: agenda.error
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Text {
            visible: agenda.error === "" && agenda.loaded && agenda.events.length === 0
            width: parent.width
            text: "Nothing on the calendar."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            horizontalAlignment: Text.AlignHCenter
          }

          Repeater {
            model: root.groups

            Column {
              id: dayColumn
              required property var modelData
              required property int index

              width: column.width
              spacing: Style.space(8)

              // Offset of this day's first row within the flattened list, so a
              // row can name its own cursor position.
              readonly property int startIndex: {
                var offset = 0
                for (var i = 0; i < dayColumn.index; i++) offset += root.groups[i].events.length
                return offset
              }

              PanelSeparator {
                visible: dayColumn.index > 0
                foreground: root.foreground
              }

              PanelSectionHeader {
                text: dayColumn.modelData.label
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              Repeater {
                model: dayColumn.modelData.events

                EventRow {
                  required property var modelData
                  required property int index

                  width: dayColumn.width
                  event: modelData
                  rowIndex: dayColumn.startIndex + index
                }
              }
            }
          }
        }
      }
    }
  }

  component EventRow: CursorSurface {
    id: row

    property var event: null
    property int rowIndex: 0

    readonly property string rowUrgency: event ? Model.urgencyFor(event.start, root.nowMs) : "normal"
    readonly property color timeColor: {
      switch (rowUrgency) {
        case "critical": return root.urgent
        case "warning": return root.accent
        case "live": return root.accent
        default: return root.dim
      }
    }

    hasCursor: root.cursorActive && root.cursorIndex === rowIndex
    foreground: root.foreground
    accent: root.accent
    implicitHeight: rowLayout.implicitHeight + Style.spacing.controlPaddingY * 2

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: row.event && row.event.url ? Qt.PointingHandCursor : Qt.ArrowCursor
      onEntered: {
        root.cursorActive = true
        root.cursorIndex = row.rowIndex
      }
      onClicked: root.openEvent(row.event)
    }

    RowLayout {
      id: rowLayout
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(10)

      Text {
        text: row.event ? Model.timeLabel(row.event.start) : ""
        color: row.timeColor
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        Layout.alignment: Qt.AlignVCenter
      }

      Text {
        text: row.event ? row.event.title : ""
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
      }

      // Marks the rows you can actually join, rather than merely attend.
      Text {
        visible: row.event && row.event.meeting === true
        text: "󰕧"
        color: row.rowUrgency === "live" ? root.accent : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        Layout.alignment: Qt.AlignVCenter
      }

      Text {
        visible: row.rowUrgency === "live"
        text: "now"
        color: root.accent
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        Layout.alignment: Qt.AlignVCenter
      }
    }
  }
}
