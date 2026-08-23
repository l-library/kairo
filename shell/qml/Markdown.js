/**
 * Markdown.js — 轻量 Markdown → HTML（QML Text 富文本）
 *
 * 支持：标题 / 粗体 / 斜体 / 行内代码 / 代码块 / 列表 / 引用 / 链接 / 分隔线 / 表格(简化)
 * v1 代码块：等宽字体 + 底色，不做逐语言高亮。
 */
.pragma library

function escapeHtml(s) {
  return String(s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
}

function inline(md, p) {
  var t = String(md)
  var codeBg = (p && p.codeBg) || "#313244"
  var codeText = (p && p.codeText) || "#cdd6f4"
  var accent = (p && p.accent) || "#89b4fa"
  // 行内代码（先保护，避免内部标记被处理）
  // 背景/文字色跟随 palette：暗色=深底亮字，亮色=浅底深字，避免黑底黑字
  var codes = {}
  var ci = 0
  t = t.replace(/`([^`]+)`/g, function (_, c) {
    codes["@@C" + ci + "@@"] = '<code style="font-family:monospace;background:' + codeBg + ';color:' + codeText + ';padding:1px 4px;border-radius:3px;">' + escapeHtml(c) + "</code>"
    return "@@C" + ci++ + "@@"
  })
  // 粗体
  t = t.replace(/\*\*([^*]+)\*\*/g, "<b>$1</b>")
  t = t.replace(/__([^_]+)__/g, "<b>$1</b>")
  // 斜体
  t = t.replace(/\*([^*]+)\*/g, "<i>$1</i>")
  t = t.replace(/_([^_]+)_/g, "<i>$1</i>")
  // 链接 [text](url)
  t = t.replace(/\[([^\]]+)\]\(([^)]+)\)/g, '<a href="$2" style="color:' + accent + ';text-decoration:none;">$1</a>')
  // 恢复行内代码
  for (var k in codes) {
    if (Object.prototype.hasOwnProperty.call(codes, k)) t = t.split(k).join(codes[k])
  }
  return t
}

/**
 * mdToHtml(markdown, palette) → HTML
 * palette: { codeBg, codeText, accent, muted, border }
 */
function mdToHtml(md, palette) {
  if (!md) return ""
  var p = palette || {}
  var codeBg = p.codeBg || "#171720"
  var codeText = p.codeText || "#cdd6f4"
  var accent = p.accent || "#89b4fa"
  var muted = p.muted || "#a6adc8"
  var border = p.border || "#45475a"

  var lines = String(md).replace(/\r\n/g, "\n").split("\n")
  var html = ""
  var inCode = false
  var inList = false
  var inQuote = false
  var tableHead = null

  function closeList() {
    if (inList) {
      html += "</ul>"
      inList = false
    }
  }
  function closeQuote() {
    if (inQuote) {
      html += "</blockquote>"
      inQuote = false
    }
  }
  function closeCode() {
    if (inCode) {
      html += "</code></pre>"
      inCode = false
    }
  }

  for (var i = 0; i < lines.length; i++) {
    var raw = lines[i]
    var line = raw

    // 代码块
    if (/^```/.test(line)) {
      if (inCode) {
        closeCode()
      } else {
        closeList(); closeQuote()
        html += '<pre style="font-family:monospace;background:' + codeBg + ';padding:8px 10px;border-radius:6px;color:' + codeText + ';white-space:pre-wrap;"><code>'
        inCode = true
      }
      continue
    }
    if (inCode) {
      html += escapeHtml(line) + "\n"
      continue
    }

    // 空行
    if (!line.trim()) {
      closeList(); closeQuote()
      html += '<br/>'
      continue
    }

    // 表格（简单处理：| a | b | 连续行 → 表格）
    if (/^\|.*\|$/.test(line)) {
      var cells = line.trim().replace(/^\||\|$/g, "").split("|").map(function (c) { return c.trim() })
      if (tableHead === null && !/^[\s:|-]+$/.test(line)) {
        tableHead = cells
        html += '<table border="0" cellspacing="0" cellpadding="3" style="border-collapse:collapse;font-size:12px;"><tr>'
        for (var c1 = 0; c1 < cells.length; c1++) html += '<th style="border-bottom:1px solid ' + border + ';text-align:left;">' + inline(cells[c1], p) + "</th>"
        html += "</tr>"
        continue
      }
      if (/^[\s:|-]+$/.test(line)) continue // 分隔行
      html += "<tr>"
      for (var c2 = 0; c2 < cells.length; c2++) html += '<td style="border-bottom:1px solid ' + border + ';">' + inline(cells[c2], p) + "</td>"
      html += "</tr>"
      continue
    }
    if (tableHead) { html += "</table>"; tableHead = null }

    // 标题
    var h = /^(#{1,4})\s+(.*)$/.exec(line)
    if (h) {
      closeList(); closeQuote()
      var level = h[1].length
      var size = level === 1 ? "17px" : level === 2 ? "15px" : level === 3 ? "14px" : "13px"
      html += '<div style="font-size:' + size + ';font-weight:bold;margin:6px 0 2px 0;">' + inline(h[2], p) + "</div>"
      continue
    }

    // 引用
    if (/^>\s?/.test(line)) {
      if (!inQuote) {
        closeList()
        html += '<blockquote style="border-left:3px solid ' + muted + ';padding-left:8px;color:' + muted + ';margin:4px 0;">'
        inQuote = true
      }
      html += "<div>" + inline(line.replace(/^>\s?/, ""), p) + "</div>"
      continue
    } else { closeQuote() }

    // 无序列表
    var li = /^[-*]\s+(.*)$/.exec(line)
    if (li) {
      if (!inList) {
        closeQuote()
        html += '<ul style="margin:4px 0;padding-left:20px;">'
        inList = true
      }
      html += '<li style="margin:2px 0;">' + inline(li[1], p) + "</li>"
      continue
    } else { closeList() }

    // 有序列表
    var oli = /^\d+[.)]\s+(.*)$/.exec(line)
    if (oli) {
      if (!inList) {
        html += '<ul style="margin:4px 0;padding-left:20px;">'
        inList = true
      }
      html += '<li style="margin:2px 0;">' + inline(oli[1], p) + "</li>"
      continue
    }

    // 分隔线
    if (/^(-{3,}|\*{3,})$/.test(line.trim())) {
      html += '<hr style="border:none;border-top:1px solid ' + border + ';margin:6px 0;"/>'
      continue
    }

    // 普通段落
    html += '<div style="margin:3px 0;">' + inline(line, p) + "</div>"
  }

  closeCode(); closeList(); closeQuote()
  if (tableHead) html += "</table>"

  // 链接点击 → 交给 UI 处理（LinkActivated）
  return html
}

/** 生成本文纯文本摘要（会话列表用） */
function plainText(md) {
  if (!md) return ""
  var t = String(md).replace(/```[\s\S]*?```/g, " [代码块] ")
    .replace(/`([^`]+)`/g, "$1")
    .replace(/[*_#>|]/g, "")
    .replace(/\[([^\]]+)\]\([^)]*\)/g, "$1")
    .replace(/\n+/g, " ")
    .trim()
  return t.length > 40 ? t.slice(0, 40) + "…" : t
}