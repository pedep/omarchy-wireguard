pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

Panel {
  id: root
  moduleName: "custom.wireguard"

  property var wireguardConnections: []
  property bool isBusy: toggleProcess.running
  property bool isImporting: importProcess.running
  property var activeConnections: []
  readonly property bool anyActive: activeConnections.length > 0

  // Omarchy Keyboard & Cursor State Variables
  property int selectedIndex: -1
  property bool cursorActive: false
  property string focusSection: "list" // "header" | "import" | "list"
  readonly property bool headerHasCursor: cursorActive && focusSection === "header"

  readonly property color hoverFill: bar ? Style.hoverFillFor(bar.foreground, Color.accent) : "transparent"
  readonly property color selectedFill: bar ? Style.selectedFillFor(bar.foreground, Color.accent) : "transparent"
  readonly property int heroRingPad: Style.space(6)

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // When opening, reset the keyboard focus
  onOpenedChanged: {
    if (opened) {
      selectedIndex = wireguardConnections.length > 0 ? 0 : -1;
      focusSection = wireguardConnections.length > 0 ? "list" : "import";
      cursorActive = false;
    }
  }

  // Function to import unimported .conf files from standard directories
  function importNewProfiles() {
    if (isImporting || isBusy)
      return;

    var script = `
    existing=$(nmcli -t -f NAME,TYPE connection show | grep ':wireguard$' | cut -d: -f1)

    for d in /etc/wireguard ~/.config/wireguard ~/wireguard; do
      if [ -d "$d" ]; then
        for f in "$d"/*.conf; do
          if [ -f "$f" ]; then
            name=$(basename "$f" .conf)
            if ! echo "$existing" | grep -q -x -- "$name"; then
              if nmcli connection import type wireguard file "$f" 2>/dev/null || pkexec nmcli connection import type wireguard file "$f" 2>/dev/null; then
                # Explicitly disable autoconnect on boot for newly imported profile
                nmcli connection modify id "$name" connection.autoconnect no 2>/dev/null
              fi
            fi
          fi
        done
      fi
    done

    # Safety check: Ensure all existing WireGuard profiles have autoconnect disabled
    echo "$existing" | while read -r name; do
    [ -n "$name" ] && nmcli connection modify id "$name" connection.autoconnect no 2>/dev/null
    done
    `;

    importProcess.command = ["bash", "-c", script];
    importProcess.running = true;
  }

  // Action function for toggling specific connections
  function toggleIndex(idx) {
    if (isBusy || idx < 0 || idx >= wireguardConnections.length)
      return;
    var conn = wireguardConnections[idx];
    var turnOn = !conn.active;
    var connName = conn.name;
    var script = "";

    if (turnOn) {
      script = "nmcli connection up id '" + connName + "'";
    } else {
      script = "nmcli connection down id '" + connName + "'";
    }

    toggleProcess.command = ["bash", "-c", script];
    toggleProcess.running = true;
  }

  // Killswitch function for the header button using nmcli
  function disableAll() {
    if (isBusy)
      return;
    var script = "nmcli -t -f NAME,TYPE connection show --active | grep ':wireguard$' | cut -d: -f1 | while read -r c; do nmcli connection down id \"$c\"; done";
    toggleProcess.command = ["bash", "-c", script];
    toggleProcess.running = true;
  }

  Component.onCompleted: listConfigs.running = true

  // 1. Fetch available WireGuard connections from NetworkManager
  Process {
    id: listConfigs
    command: ["bash", "-c", "nmcli -t -f NAME,TYPE connection show | grep ':wireguard$' | cut -d: -f1 || true"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: function () {
        var lines = String(text || "").trim().split("\n");
        var newConns = [];
        for (var i = 0; i < lines.length; i++) {
          var name = lines[i].trim();
          if (name.length > 0) {
            newConns.push({
              name: name,
              active: false
            });
          }
        }
        root.wireguardConnections = newConns;
        checkStatus.running = true;
      }
    }
  }

  // 2. Fetch active WireGuard connections from NetworkManager
  Process {
    id: checkStatus
    command: ["bash", "-c", "nmcli -t -f NAME,TYPE connection show --active | grep ':wireguard$' | cut -d: -f1 || true"]
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: function () {
        var activeArr = String(text || "").trim().split("\n");
        var conns = root.wireguardConnections.slice();
        var activeNames = [];

        for (var i = 0; i < conns.length; i++) {
          var isActive = (activeArr.indexOf(conns[i].name) !== -1);
          conns[i].active = isActive;
          if (isActive)
            activeNames.push(conns[i].name);
        }

        root.wireguardConnections = conns;
        root.activeConnections = activeNames;
      }
    }
  }

  // 3. Keep status in sync
  Timer {
    interval: 3000
    running: true
    repeat: true
    onTriggered: checkStatus.running = true
  }

  Process {
    id: toggleProcess
    running: false
    onExited: function (exitCode) {
      checkStatus.running = true;
    }
  }

  // Process for importing new profiles
  Process {
    id: importProcess
    running: false
    onExited: function (exitCode) {
      listConfigs.running = true; // Refresh connection list after import completes
    }
  }

  // ---------- Top Bar Icon Button ----------
  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰖂"
    foreground: root.anyActive ? root.bar.foreground : Qt.darker(root.bar.foreground, 1.2)

    onPressed: function (b) {
      if (root.opened) {
        root.close();
      } else {
        root.open();
        listConfigs.running = true;
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(320))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onMoveRequested: function (dx, dy) {
        if (!root.cursorActive) {
          root.cursorActive = true;
          if (dy >= 0)
            return;
        }
        if (dy !== 0) {
          if (root.focusSection === "header") {
            if (dy > 0)
              root.focusSection = "import";
          } else if (root.focusSection === "import") {
            if (dy < 0)
              root.focusSection = "header";
            else if (dy > 0 && root.wireguardConnections.length > 0) {
              root.focusSection = "list";
              root.selectedIndex = 0;
            }
          } else if (root.focusSection === "list") {
            if (dy < 0 && root.selectedIndex <= 0) {
              root.focusSection = "import";
            } else {
              var newIdx = root.selectedIndex + dy;
              root.selectedIndex = Math.max(0, Math.min(root.wireguardConnections.length - 1, newIdx));
            }
          }
        }
      }

      onActivateRequested: {
        if (root.cursorActive) {
          if (root.focusSection === "header")
            root.disableAll();
          else if (root.focusSection === "import")
            root.importNewProfiles();
          else if (root.focusSection === "list")
            root.toggleIndex(root.selectedIndex);
        }
      }
      onCloseRequested: root.close()
      onTabRequested: function (direction) {
        root.switchPanel(direction);
      }
      onTextKey: function (t) {
        if (t === "r" || t === "R")
          listConfigs.running = true;
      }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(12)

        // ---------- Hero Section ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight) + root.heroRingPad * 2

          // Keyboard Focus Ring for the Hero Toggle
          BorderSurface {
            anchors.fill: heroIcon
            anchors.margins: -root.heroRingPad
            color: "transparent"
            radius: Style.cornerRadius
            visible: root.headerHasCursor && root.anyActive
            borderSpec: Border.controlSpec("hover-cursor", root.bar.foreground, Color.accent)
          }

          Text {
            id: heroIcon
            text: "󰖂"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.display
            opacity: root.anyActive ? 1.0 : 0.5
            anchors.left: parent.left
            anchors.leftMargin: root.heroRingPad
            anchors.verticalCenter: parent.verticalCenter

            MouseArea {
              id: heroIconMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: root.anyActive ? Qt.PointingHandCursor : Qt.ArrowCursor
              onContainsMouseChanged: if (containsMouse) {
                root.cursorActive = true;
                root.focusSection = "header";
              }
              // Clicking the hero acts as a "Killswitch" for all WG connections
              onClicked: root.disableAll()
            }
            PanelToolTip {
              visible: heroIconMouse.containsMouse && root.anyActive
              text: "Disable VPN"
              fontFamily: root.bar.fontFamily
            }
          }

          Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(14)
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              text: root.anyActive ? (root.activeConnections.length > 1 ? root.activeConnections[0] + " +" + (root.activeConnections.length - 1) : root.activeConnections[0]) : "WireGuard"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
              width: parent.width
            }

            Text {
              text: root.anyActive ? (root.activeConnections.length + (root.activeConnections.length === 1 ? " CONNECTION ACTIVE" : " CONNECTIONS ACTIVE")) : "NOT CONNECTED"
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              elide: Text.ElideRight
              width: parent.width
            }
          }

          Button {
            id: importBtn
            text: root.isImporting ? "" : "󰦛"
            tooltipText: "Discover confguration files"
            enabled: !root.isImporting && !root.isBusy
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            fontSize: Style.font.body
            horizontalPadding: 6
            verticalPadding: 4
            bordered: true
            hasCursor: root.cursorActive && root.focusSection === "import"
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter

            onHovered: function (isHovered) {
              if (isHovered) {
                root.cursorActive = true;
                root.focusSection = "import";
              }
            }
            onClicked: root.importNewProfiles()
          }
        }

        PanelSeparator {
          foreground: root.bar.foreground
        }

        // ---------- Section Header with "Load Profiles" Button ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(sectionHeader.implicitHeight, infoBtn.implicitHeight)

          PanelSectionHeader {
            id: sectionHeader
            text: "CONNECTIONS"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            fontSize: Style.font.body
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
          }

          Button {
            id: infoBtn
            text: "󰋼"
            tooltipText: "All .conf files placed in:\n\n ~/.config/wireguard/\n ~/wiregaurd/\n\nwill be discovered"
            enabled: false
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            fontSize: Style.font.body + 4
            horizontalPadding: 6
            verticalPadding: 2
            bordered: false
            hasCursor: false
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        // ---------- Connections List ----------
        ListView {
          id: connectionList
          width: parent.width
          height: Math.min(contentHeight, Style.space(300))
          spacing: Style.space(4)
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          interactive: contentHeight > height

          ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AsNeeded
          }

          model: root.wireguardConnections

          // Allow keyboard scrolling to keep the focused item in view
          currentIndex: root.focusSection === "list" ? root.selectedIndex : -1
          onCurrentIndexChanged: if (currentIndex >= 0)
            positionViewAtIndex(currentIndex, ListView.Contain)

          delegate: Item {
            required property var modelData
            required property int index

            width: ListView.view.width
            height: delegateRow.implicitHeight

            WgRow {
              id: delegateRow
              width: parent.width
              conn: modelData
              rowIndex: parent.index
            }
          }
        }
      }
    }
  }

  // ---------- Custom Row Component ----------
  component WgRow: CursorSurface {
    id: row
    required property var conn
    required property int rowIndex

    readonly property bool isConnected: conn.active
    readonly property bool isSelected: root.focusSection === "list" && root.selectedIndex === rowIndex

    hasCursor: root.cursorActive && isSelected
    current: isConnected
    foreground: root.bar.foreground
    fill: root.hoverFill
    currentFill: root.selectedFill

    implicitHeight: rowBody.implicitHeight + Style.spacing.rowPaddingX * 2

    MouseArea {
      id: rowMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      enabled: !root.isBusy

      onContainsMouseChanged: if (containsMouse) {
        root.cursorActive = true;
        root.focusSection = "list";
        root.selectedIndex = row.rowIndex;
      }
      onClicked: root.toggleIndex(row.rowIndex)
    }

    Item {
      id: rowBody
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      implicitHeight: Math.max(wgIcon.implicitHeight, wgInfo.implicitHeight)

      Text {
        id: wgIcon
        text: "󰖂"
        color: row.isConnected ? root.bar.foreground : Qt.darker(root.bar.foreground, 1.5)
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.title
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
      }

      Column {
        id: wgInfo
        spacing: Style.space(1)
        anchors.left: wgIcon.right
        anchors.leftMargin: Style.space(10)
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter

        Text {
          text: row.conn.name
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
          width: parent.width
        }

        Text {
          text: {
            if (root.isBusy && toggleProcess.command[2].indexOf(row.conn.name) !== -1)
              return "Waiting...";
            if (row.isConnected)
              return "Connected";
            return "";
          }
          visible: text !== ""
          height: visible ? implicitHeight : 0
          color: row.isConnected ? root.bar.foreground : Qt.darker(root.bar.foreground, 1.5)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
          width: parent.width
        }
      }
    }
  }
}
