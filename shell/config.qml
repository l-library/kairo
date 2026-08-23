import Quickshell
import Quickshell.Io
import QtQuick
import "qml"

/**
 * config.qml — kairo 浮窗入口
 *
 * 位置：左边缘垂直居中（layer-shell 未锚定维度自动居中）
 * 动画：显示时从左侧滑入（QML Translate，Hyprland 的窗口动画不作用于 layer 窗口）
 * 唤起：Hyprland keybind 执行 scripts/toggle-kairo.sh
 *   - 未运行时：quickshell -p <config>
 *   - 已运行时：quickshell ipc call kairo toggle（原生 IPC，无需 DBus）
 */
PanelWindow {
  id: panel
  visible: false
  implicitWidth: 500
  implicitHeight: 680
  color: "transparent"

  // 左边缘、垂直居中
  anchors {
    left: true
  }
  margins {
    left: 12
  }
  exclusiveZone: 0
  exclusionMode: ExclusionMode.Ignore
  aboveWindows: true
  focusable: true

  // 主题单例控制权归这里；client.theme 变化时跟随（含初始连接拉取）
  Theme {
    id: theme
  }
  Binding {
    target: theme
    property: "palette"
    value: client.theme
  }

  KairoClient {
    id: client
  }

  // 滑入动画容器：整块内容（含 ChatPanel 背景）从左侧平移进入
  Item {
    id: panelContent
    anchors.fill: parent
    clip: true
    opacity: 1
    transform: Translate { id: slideTranslate; x: 0 }

    ChatPanel {
      id: chat
      anchors.fill: parent
      radius: 14
      theme: theme
      client: client
      focus: true
      onHideRequested: panel.hidePanel()
      onThemeToggleRequested: panel.toggleTheme()
    }
  }

  // ---------------- 动画 ----------------
  property bool hiding: false

  // 显示：淡入 + 从左滑入
  ParallelAnimation {
    id: showAnim
    NumberAnimation {
      target: panelContent; property: "opacity"; from: 0; to: 1; duration: 220; easing.type: Easing.OutCubic
    }
    NumberAnimation {
      target: slideTranslate; property: "x"; to: 0; duration: 280; easing.type: Easing.OutCubic
    }
  }
  // 隐藏：快速缩回左侧屏幕外（160ms，保持即点即走）
  NumberAnimation {
    id: slideOut
    target: slideTranslate
    property: "x"
    to: 0
    duration: 160
    easing.type: Easing.InQuad
    onRunningChanged: if (!running && panel.hiding) panel.finishHide()
  }

  function showPanel() {
    panel.hiding = false
    // 若正在滑出，立即取消并把内容摆回原位
    if (slideOut.running) { slideOut.stop(); slideTranslate.x = 0 }
    slideTranslate.x = -(panel.width + 24) // 从左侧屏幕外开始
    panelContent.opacity = 0
    panel.visible = true
    // 重置动画 from（x 位置已在上面设定）
    showAnim.running = false
    showAnim.start()
    Qt.callLater(chat.focusEditor)
  }

  function hidePanel() {
    if (panel.hiding || !panel.visible) return
    panel.hiding = true
    // 快速滑出（向右缩回不可见即可，层窗口透明背景无视觉泄漏）
    slideOut.to = -(panel.width + 24)
    slideOut.start()
  }

  function finishHide() {
    panel.hiding = false
    panel.visible = false
    slideTranslate.x = 0
    panelContent.opacity = 1
  }

  // 兜底：任何外部置 visible=false（如异常路径）都复位动画状态
  onVisibleChanged: {
    if (!visible && !panel.hiding) {
      slideTranslate.x = 0
      panelContent.opacity = 1
    }
  }

  // ---------------- 主题 ----------------
  function toggleTheme() {
    var next = theme.palette === "dark" ? "light" : "dark"
    client.setTheme(next)
  }

  // ---------------- 原生 IPC ----------------
  IpcHandler {
    target: "kairo"

    function toggle(): void {
      if (panel.visible) panel.hidePanel()
      else panel.showPanel()
    }

    function show(): void {
      panel.showPanel()
    }

    function hide(): void {
      panel.hidePanel()
    }

    function isVisible(): bool {
      return panel.visible
    }

    function setTheme(t: string): void {
      client.setTheme(t)
    }

    function getTheme(): string {
      return theme.palette
    }

    function getDebugInfo(): string {
      return JSON.stringify({
        connected: client.connected,
        mode: client.mode,
        theme: theme.palette,
        sessionId: client.sessionId,
        sessionCount: client.sessions.length,
        streaming: client.streaming,
        pendingApproval: client.pendingApproval ? client.pendingApproval.id : null,
        layout: chat.getLayoutDebug(),
      })
    }

    // 侧边栏：IPC 呼出/收起（可绑自定义快捷键）
    function toggleSidebar(): void {
      chat.setSidebarOpen(!chat.getSidebarOpen())
    }
  }

  Component.onCompleted: {
    client.connectToDaemon()
  }
}