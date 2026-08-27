import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts

/**
 * SessionSidebar.qml — kairo 侧边栏（点击标题栏 ☰ 呼出）
 *
 * 两个标签：
 *  - 会话：纵向会话列表（命名/首条摘要/消息数、活动高亮、两步确认删除）
 *  - 设置：提供商（添加/移除）+ 技能（只读展示）+ pi 插件（列表/安装/移除）
 *
 * 注意：
 *  - 交互命中顺序：整行 MouseArea 声明在底层，删除按钮 MouseArea 在
 *    RowLayout 上方（后声明 = 更上层），修复“行点击吞掉删除按钮”bug
 *  - armed 状态统一用 delegate 根（row）的单一来源；按钮色用纯绑定
 *  - 用 x/y 定位（topOffset/bottomOffset），anchors 会覆盖 x 导致常驻
 */
Item {
  id: sb
  width: 260

  /** 由 ChatPanel 传入：y 起点（标题栏下方）与可用高度（到输入栏上方） */
  property real topOffset: 34
  property real bottomOffset: 65
  y: topOffset
  height: Math.max(0, (parent ? parent.height : 0) - topOffset - bottomOffset)

  property var theme: null
  property var i18n: null // I18n 实例注入
  property var sessions: []
  property string activeSessionId: ""
  property var skills: []
  property var plugins: []
  property var providers: []
  property string currentProvider: ""
  property bool providerBusy: false
  property bool pluginBusy: false
  property int tab: 0 // 0=会话 1=设置
  property bool open: false
  signal newSessionRequested()
  signal activateRequested(string id)
  signal deleteRequested(string id)
  signal skillsRequested()
  signal pluginsRequested()
  signal installRequested(string source)
  signal removeRequested(string source)
  signal providersRequested()
  signal providerAddRequested(string id, string apiKey, string baseUrl)
  signal providerRemoveRequested(string id)

  // 滑入滑出：x 为负时整体移出面板左缘，由面板 clip 裁掉
  x: open ? 0 : -(width + 12)
  Behavior on x {
    NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
  }

  // 会话显示名：会话名 > 首条消息摘要 > “新会话”
  function sessionLabel(s) {
    if (s.name && s.name !== "") return s.name
    var fm = String(s.firstMessage || "").trim().replace(/\s+/g, " ")
    if (fm !== "") return fm.length > 16 ? fm.slice(0, 16) + "…" : fm
    return sb.i18n ? sb.i18n.tr("sidebar.newSession") : "新会话"
  }

  Rectangle {
    anchors.fill: parent
    color: theme ? theme.bgAlt : "#181825"
    border.color: theme ? theme.border : "#45475a"
    border.width: 1

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: 10
      spacing: 8

      // ---- 头部：标签切换 + 关闭 ----
      RowLayout {
        Layout.fillWidth: true
        spacing: 6

        RowLayout {
          Layout.fillWidth: true
          spacing: 4

          // 会话 tab
          Rectangle {
            id: tabSessions
            Layout.fillWidth: true
            height: 24
            radius: 6
            color: sb.tab === 0 ? (theme ? theme.accent : "#89b4fa") : (theme ? theme.surface : "#313244")
            Text {
              anchors.centerIn: parent
              text: sb.i18n ? sb.i18n.tr("sidebar.sessions", { n: sb.sessions.length }) : "会话 (" + sb.sessions.length + ")"
              color: sb.tab === 0 ? "#ffffff" : (theme ? theme.subtext : "#a6adc8")
              font.pixelSize: 11
              font.bold: sb.tab === 0
            }
            MouseArea {
              anchors.fill: parent
              onClicked: sb.tab = 0
            }
          }

          // 设置 tab
          Rectangle {
            id: tabExt
            Layout.fillWidth: true
            height: 24
            radius: 6
            color: sb.tab === 1 ? (theme ? theme.accent : "#89b4fa") : (theme ? theme.surface : "#313244")
            Text {
              anchors.centerIn: parent
              text: sb.i18n ? sb.i18n.tr("sidebar.settings", { n: sb.providers.length + sb.skills.length + sb.plugins.length }) : "设置 (" + (sb.providers.length + sb.skills.length + sb.plugins.length) + ")"
              color: sb.tab === 1 ? "#ffffff" : (theme ? theme.subtext : "#a6adc8")
              font.pixelSize: 11
              font.bold: sb.tab === 1
            }
            MouseArea {
              anchors.fill: parent
              onClicked: {
                sb.tab = 1
                sb.skillsRequested()
                sb.pluginsRequested()
                sb.providersRequested()
              }
            }
          }
        }

        Text {
          text: "✕"
          font.pixelSize: 13
          color: theme ? theme.muted : "#6c7086"
          MouseArea {
            anchors.fill: parent
            onClicked: sb.open = false
          }
        }
      }

      // ================= 标签 0：会话 =================
      ColumnLayout {
        visible: sb.tab === 0
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 8

        // 新建
        Rectangle {
          id: newBtn
          Layout.fillWidth: true
          height: 30
          radius: 6
          color: theme ? theme.surface : "#313244"
          Text {
            anchors.centerIn: parent
            text: sb.i18n ? sb.i18n.tr("sidebar.newBtn") : "＋ 新建会话"
            color: theme ? theme.subtext : "#a6adc8"
            font.pixelSize: 12
          }
          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onClicked: sb.newSessionRequested()
            onEntered: newBtn.color = theme ? theme.surfaceHover : "#3b4261"
            onExited: newBtn.color = theme ? theme.surface : "#313244"
          }
        }

        // 会话列表
        ListView {
          id: list
          Layout.fillWidth: true
          Layout.fillHeight: true
          clip: true
          spacing: 4
          model: sb.sessions
          delegate: Rectangle {
            id: row
            required property var modelData
            readonly property bool isActive: modelData.id === sb.activeSessionId
            property bool armed: false
            width: list.width
            height: 48
            radius: 8
            color: isActive
              ? (theme ? theme.accent : "#89b4fa")
              : (rowMA.containsMouse ? (theme ? theme.surfaceHover : "#3b4261") : (theme ? theme.surface : "#313244"))

            // 整行点击区：声明在最底层（z 最下），不遮挡删除按钮
            MouseArea {
              id: rowMA
              anchors.fill: parent
              hoverEnabled: true
              onClicked: {
                // 处于确认态时点击行 = 取消确认，不切换会话
                if (row.armed) { row.armed = false; return }
                if (!isActive) sb.activateRequested(modelData.id)
              }
            }

            RowLayout {
              anchors.fill: parent
              anchors.leftMargin: 10
              anchors.rightMargin: 6
              anchors.verticalCenter: parent.verticalCenter
              spacing: 8

              ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Text {
                  Layout.fillWidth: true
                  text: sb.sessionLabel(modelData)
                  color: isActive ? "#ffffff" : (theme ? theme.text : "#cdd6f4")
                  font.pixelSize: 12
                  font.bold: isActive
                  elide: Text.ElideRight
                }
                Text {
                  visible: !isActive && modelData.firstMessage && String(modelData.firstMessage).trim() !== "" && modelData.name !== modelData.firstMessage
                  Layout.fillWidth: true
                  text: String(modelData.firstMessage || "").trim().replace(/\s+/g, " ")
                  color: isActive ? "#ffffff" : (theme ? theme.muted : "#6c7086")
                  font.pixelSize: 9
                  elide: Text.ElideRight
                }
              }

              // 消息数
              Text {
                visible: !isActive && (modelData.messageCount || 0) > 0
                text: String(modelData.messageCount || 0)
                font.pixelSize: 9
                color: isActive ? "#ffffff" : (theme ? theme.faint : "#585b70")
              }

              // 删除按钮（两步确认）。后声明 = 在行点击区之上，点击优先到删除
              Rectangle {
                id: delBtn
                visible: !isActive
                width: row.armed ? 64 : 22
                height: 22
                radius: 5
                // 纯绑定：armed→红底；悬停→浅色。不用 onEntered 赋值（会破坏绑定）
                color: row.armed
                  ? (theme ? theme.red : "#f38ba8")
                  : (delMA.containsMouse ? (theme ? theme.surfaceHover : "#3b4261") : "transparent")
                Text {
                  anchors.centerIn: parent
                  text: row.armed ? (sb.i18n ? sb.i18n.tr("sidebar.confirmDelete") : "确认删除") : "🗑"
                  color: row.armed ? "#ffffff" : (theme ? theme.muted : "#6c7086")
                  font.pixelSize: row.armed ? 10 : 9
                }
                MouseArea {
                  id: delMA
                  anchors.fill: parent
                  hoverEnabled: true
                  onClicked: {
                    if (row.armed) {
                      row.armed = false
                      sb.deleteRequested(modelData.id)
                    } else {
                      row.armed = true
                      disarmTimer.restart()
                    }
                  }
                }
                Timer {
                  id: disarmTimer
                  interval: 3000
                  onTriggered: row.armed = false
                }
              }
            }
          }
        }
      }

      // ================= 标签 1：设置 =================
      Flickable {
        visible: sb.tab === 1
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        contentHeight: extCol.implicitHeight
        Column {
          id: extCol
          width: parent.width
          spacing: 10

          // ============ 提供商 ============
          Text {
            text: sb.i18n ? sb.i18n.tr("sidebar.providers", { n: sb.providers.length }) : "提供商 (" + sb.providers.length + ")"
            font.pixelSize: 11
            font.bold: true
            color: theme ? theme.text : "#cdd6f4"
          }
          ListView {
            id: provList
            width: parent.width
            height: Math.min(120, Math.max(24, (sb.providers || []).length * 30))
            clip: true
            spacing: 2
            model: sb.providers || []
            delegate: Rectangle {
              required property var modelData
              readonly property bool isCurrent: modelData.id === sb.currentProvider
              width: provList.width
              height: 28
              radius: 5
              color: theme ? theme.surface : "#313244"
              RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 6
                spacing: 6
                Text {
                  text: modelData.id
                  color: theme ? theme.text : "#cdd6f4"
                  font.pixelSize: 10
                  font.bold: true
                  Layout.preferredWidth: 110
                  elide: Text.ElideRight
                }
                Text {
                  text: modelData.authed ? (sb.i18n ? sb.i18n.tr("sidebar.authed") : "已鉴权") : (sb.i18n ? sb.i18n.tr("sidebar.unauth") : "未鉴权")
                  color: modelData.authed ? (theme ? theme.green : "#a6e3a1") : (theme ? theme.yellow : "#f9e2af")
                  font.pixelSize: 8
                }
                Text {
                  text: sb.i18n ? sb.i18n.tr("sidebar.modelsCount", { n: modelData.modelCount || 0 }) : String(modelData.modelCount || 0) + " 模型"
                  color: theme ? theme.muted : "#6c7086"
                  font.pixelSize: 8
                }
                Item { Layout.fillWidth: true }
                Rectangle {
                  id: provDel
                  visible: modelData.removable && !isCurrent
                  width: 22
                  height: 20
                  radius: 4
                  color: provDelMA.containsMouse ? (theme ? theme.red : "#f38ba8") : "transparent"
                  Text {
                    anchors.centerIn: parent
                    text: "✕"
                    color: provDelMA.containsMouse ? "#ffffff" : (theme ? theme.muted : "#6c7086")
                    font.pixelSize: 10
                  }
                  MouseArea {
                    id: provDelMA
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: sb.providerRemoveRequested(modelData.id)
                  }
                }
              }
            }
          }
          Text {
            text: sb.i18n ? sb.i18n.tr("sidebar.addProviderNote") : "添加提供商（baseUrl 留空则用 SDK 内置目录）"
            color: theme ? theme.faint : "#585b70"
            font.pixelSize: 9
            wrapMode: Text.Wrap
            width: parent.width
          }
          // id
          RowLayout {
            width: parent.width
            spacing: 6
            Text {
              text: "id"
              color: theme ? theme.muted : "#6c7086"
              font.pixelSize: 10
              width: 40
            }
            Rectangle {
              Layout.fillWidth: true
              height: 26
              radius: 6
              color: theme ? theme.surfaceAlt : "#242437"
              border.color: theme ? theme.border : "#45475a"
              QC.TextField {
                id: provIdInput
                anchors.fill: parent
                anchors.margins: 2
                background: null
                placeholderText: sb.i18n ? sb.i18n.tr("sidebar.providerIdPlaceholder") : "如 my-llm"
                placeholderTextColor: theme ? theme.muted : "#6c7086"
                color: theme ? theme.text : "#cdd6f4"
                font.pixelSize: 10
                selectByMouse: true
              }
            }
          }
          // api key
          RowLayout {
            width: parent.width
            spacing: 6
            Text {
              text: "api key"
              color: theme ? theme.muted : "#6c7086"
              font.pixelSize: 10
              width: 40
            }
            Rectangle {
              Layout.fillWidth: true
              height: 26
              radius: 6
              color: theme ? theme.surfaceAlt : "#242437"
              border.color: theme ? theme.border : "#45475a"
              QC.TextField {
                id: provKeyInput
                anchors.fill: parent
                anchors.margins: 2
                background: null
                placeholderText: "sk-…"
                placeholderTextColor: theme ? theme.muted : "#6c7086"
                color: theme ? theme.text : "#cdd6f4"
                font.pixelSize: 10
                echoMode: TextInput.Password
                selectByMouse: true
              }
            }
          }
          // baseUrl + 添加
          RowLayout {
            width: parent.width
            spacing: 6
            Text {
              text: "baseUrl"
              color: theme ? theme.muted : "#6c7086"
              font.pixelSize: 10
              width: 40
            }
            Rectangle {
              Layout.fillWidth: true
              height: 26
              radius: 6
              color: theme ? theme.surfaceAlt : "#242437"
              border.color: theme ? theme.border : "#45475a"
              QC.TextField {
                id: provUrlInput
                anchors.fill: parent
                anchors.margins: 2
                background: null
                placeholderText: sb.i18n ? sb.i18n.tr("sidebar.baseUrlPlaceholder") : "可选，OpenAI 兼容端点"
                placeholderTextColor: theme ? theme.muted : "#6c7086"
                color: theme ? theme.text : "#cdd6f4"
                font.pixelSize: 10
                selectByMouse: true
              }
            }
            Rectangle {
              id: provAddBtn
              width: 62
              height: 26
              radius: 6
              color: sb.providerBusy ? (theme ? theme.yellow : "#f9e2af") : (theme ? theme.accent : "#89b4fa")
              Text {
                anchors.centerIn: parent
                text: sb.providerBusy
                  ? (sb.i18n ? sb.i18n.tr("sidebar.adding") : "添加中…")
                  : (sb.i18n ? sb.i18n.tr("sidebar.add") : "添加")
                color: theme ? theme.onAccent : "#ffffff"
                font.pixelSize: 10
                font.bold: true
              }
              MouseArea {
                anchors.fill: parent
                enabled: !sb.providerBusy
                onClicked: {
                  var pid = provIdInput.text.trim()
                  var key = provKeyInput.text.trim()
                  if (pid === "" || key === "") return
                  provIdInput.text = ""
                  provKeyInput.text = ""
                  provUrlInput.text = ""
                  sb.providerAddRequested(pid, key, provUrlInput.text.trim())
                }
              }
            }
          }

          // ============ 技能（只读展示） ============
          Text {
            text: sb.i18n ? sb.i18n.tr("sidebar.skills", { n: sb.skills.length }) : "技能 (" + sb.skills.length + ")"
            font.pixelSize: 11
            font.bold: true
            color: theme ? theme.text : "#cdd6f4"
          }
          ListView {
            id: skillList
            width: parent.width
            height: Math.min(120, Math.max(24, (sb.skills || []).length * 30))
            clip: true
            spacing: 2
            model: sb.skills || []
            delegate: Rectangle {
              required property var modelData
              width: skillList.width
              height: 28
              radius: 5
              color: theme ? theme.surface : "#313244"
              RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                spacing: 6
                Text {
                  text: modelData.name
                  color: theme ? theme.text : "#cdd6f4"
                  font.pixelSize: 10
                  font.bold: true
                  Layout.preferredWidth: 90
                  elide: Text.ElideRight
                }
                Text {
                  Layout.fillWidth: true
                  text: String(modelData.description || "").split("\n")[0]
                  color: theme ? theme.muted : "#6c7086"
                  font.pixelSize: 9
                  elide: Text.ElideRight
                }
              }
            }
          }
          Text {
            text: sb.i18n ? sb.i18n.tr("sidebar.skillsManualNote") : "手动安装技能见 docs/skills.md · 或直接问我"
            color: theme ? theme.faint : "#585b70"
            font.pixelSize: 9
            wrapMode: Text.Wrap
            width: parent.width
          }

          // ============ pi 插件 ============
          Text {
            text: sb.i18n ? sb.i18n.tr("sidebar.plugins", { n: sb.plugins.length }) : "插件 (" + sb.plugins.length + ")"
            font.pixelSize: 11
            font.bold: true
            color: theme ? theme.text : "#cdd6f4"
          }
          ListView {
            id: pluginList
            width: parent.width
            height: Math.min(140, Math.max(24, (sb.plugins || []).length * 28))
            clip: true
            spacing: 2
            model: sb.plugins || []
            delegate: Rectangle {
              required property var modelData
              width: pluginList.width
              height: 28
              radius: 5
              color: theme ? theme.surface : "#313244"
              RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 6
                spacing: 6
                Text {
                  Layout.fillWidth: true
                  text: modelData.source
                  color: theme ? theme.text : "#cdd6f4"
                  font.pixelSize: 10
                  elide: Text.ElideRight
                }
                Text {
                  text: modelData.scope === "project"
                    ? (sb.i18n ? sb.i18n.tr("sidebar.scopeProject") : "项目")
                    : (sb.i18n ? sb.i18n.tr("sidebar.scopeUser") : "用户")
                  color: theme ? theme.faint : "#585b70"
                  font.pixelSize: 8
                }
                Rectangle {
                  id: del2
                  width: 22
                  height: 20
                  radius: 4
                  color: del2MA.containsMouse ? (theme ? theme.red : "#f38ba8") : "transparent"
                  Text {
                    anchors.centerIn: parent
                    text: "✕"
                    color: del2MA.containsMouse ? "#ffffff" : (theme ? theme.muted : "#6c7086")
                    font.pixelSize: 10
                  }
                  MouseArea {
                    id: del2MA
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: sb.removeRequested(modelData.source)
                  }
                }
              }
            }
          }
          RowLayout {
            width: parent.width
            spacing: 6
            Rectangle {
              Layout.fillWidth: true
              height: 26
              radius: 6
              color: theme ? theme.surfaceAlt : "#242437"
              border.color: theme ? theme.border : "#45475a"
              QC.TextField {
                id: pluginInput
                anchors.fill: parent
                anchors.margins: 2
                background: null
                placeholderText: sb.i18n ? sb.i18n.tr("sidebar.pluginPlaceholder") : "npm 包名 / git 地址…"
                placeholderTextColor: theme ? theme.faint : "#585b70"
                color: theme ? theme.text : "#cdd6f4"
                font.pixelSize: 10
                selectByMouse: true
              }
            }
            Rectangle {
              id: addBtn
              width: 62
              height: 26
              radius: 6
              color: sb.pluginBusy ? (theme ? theme.yellow : "#f9e2af") : (theme ? theme.accent : "#89b4fa")
              Text {
                anchors.centerIn: parent
                text: sb.pluginBusy
                  ? (sb.i18n ? sb.i18n.tr("sidebar.installing") : "安装中…")
                  : (sb.i18n ? sb.i18n.tr("sidebar.install") : "安装")
                color: theme ? theme.onAccent : "#ffffff"
                font.pixelSize: 10
                font.bold: true
              }
              MouseArea {
                anchors.fill: parent
                enabled: !sb.pluginBusy
                onClicked: {
                  var src = pluginInput.text.trim()
                  if (src === "") return
                  pluginInput.text = ""
                  sb.installRequested(src)
                }
              }
            }
          }
        }
      }
    }
  }
}