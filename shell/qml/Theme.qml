import QtQuick

/**
 * Theme.qml — kairo 双主题色板（深/浅）
 *
 * 用法：config.qml 里实例化一份（id: theme），传给各组件。
 * 切换：Theme.palette 或直接赋值 theme.palette = "light"，所有绑定自动联动。
 */
Item {
  id: theme
  width: 0
  height: 0

  property string palette: "dark" // "dark" | "light"

  // ---------- 深色（默认，Catppuccin Mocha 系） ----------
  readonly property color d_bg: "#1e1e2e"
  readonly property color d_bgAlt: "#181825"
  readonly property color d_surface: "#313244"
  readonly property color d_surfaceHover: "#3b4261"
  readonly property color d_surfaceAlt: "#242437"
  readonly property color d_codeBg: "#171720"
  readonly property color d_text: "#cdd6f4"
  readonly property color d_subtext: "#a6adc8"
  readonly property color d_muted: "#6c7086"
  readonly property color d_faint: "#585b70"
  readonly property color d_border: "#45475a"
  readonly property color d_accent: "#89b4fa"
  readonly property color d_green: "#a6e3a1"
  readonly property color d_red: "#f38ba8"
  readonly property color d_yellow: "#f9e2af"
  readonly property color d_divider: "#2a2b3a"
  readonly property color d_overlay: "#80000000"
  readonly property color d_emptyHint: "#45475a"
  // 用户消息气泡：surface 混入 accent 的蓝调，与助手灰调气泡区分
  readonly property color d_userBubble: "#4b597a"

  // ---------- 浅色（GitHub 风格） ----------
  readonly property color l_bg: "#f6f8fa"
  readonly property color l_bgAlt: "#eaeef2"
  readonly property color l_surface: "#e9edf2"
  readonly property color l_surfaceHover: "#dde4ec"
  readonly property color l_surfaceAlt: "#eef1f5"
  readonly property color l_codeBg: "#f1f3f6"
  readonly property color l_text: "#1f2328"
  readonly property color l_subtext: "#57606a"
  readonly property color l_muted: "#8a939d"
  readonly property color l_faint: "#aab2bb"
  readonly property color l_border: "#d0d7de"
  readonly property color l_accent: "#0969da"
  readonly property color l_green: "#1a7f37"
  readonly property color l_red: "#cf222e"
  readonly property color l_yellow: "#9a6700"
  readonly property color l_divider: "#d8dee4"
  readonly property color l_overlay: "#40ffffff"
  readonly property color l_emptyHint: "#b0b8c0"
  // 用户消息气泡（浅色）：#e9edf2 混入 accent #0969da
  readonly property color l_userBubble: "#c7d9ee"

  // ---------- 当前主题色 ----------
  readonly property bool isDark: palette === "dark"

  readonly property color bg: isDark ? d_bg : l_bg
  readonly property color bgAlt: isDark ? d_bgAlt : l_bgAlt
  readonly property color surface: isDark ? d_surface : l_surface
  readonly property color surfaceHover: isDark ? d_surfaceHover : l_surfaceHover
  readonly property color surfaceAlt: isDark ? d_surfaceAlt : l_surfaceAlt
  readonly property color codeBg: isDark ? d_codeBg : l_codeBg
  readonly property color text: isDark ? d_text : l_text
  readonly property color subtext: isDark ? d_subtext : l_subtext
  readonly property color muted: isDark ? d_muted : l_muted
  readonly property color faint: isDark ? d_faint : l_faint
  readonly property color border: isDark ? d_border : l_border
  readonly property color accent: isDark ? d_accent : l_accent
  readonly property color green: isDark ? d_green : l_green
  readonly property color red: isDark ? d_red : l_red
  readonly property color yellow: isDark ? d_yellow : l_yellow
  readonly property color divider: isDark ? d_divider : l_divider
  readonly property color overlay: isDark ? d_overlay : l_overlay
  readonly property color emptyHint: isDark ? d_emptyHint : l_emptyHint
  readonly property color userBubble: isDark ? d_userBubble : l_userBubble
  /** 彩色按钮上的文字色（绿/蓝/红底） */
  readonly property color onAccent: isDark ? "#1e1e2e" : "#ffffff"
}