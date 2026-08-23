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

// ================= 对话段检测 =================
//
// 用途：AI 一次输出里常混有多段对话（小明：… / 小红：… 连续多行），
// 渲染层需要把它们拆成独立的气泡卡片，避免全部连成一大段。

/**
 * speakerParts(line) → { name, rest } 或 null
 * 解析"说话人：内容"行，兼容 Markdown 前缀（- 1. >）。
 * 排除"标签型"冒号句（注意：/功能：/优点：…），避免把说明清单误判成对话。
 */
function speakerParts(line) {
  var l = String(line).trim()
  // 兼容 Markdown 列表/引用前缀：- 小明：…  1. 小明：…  > 小明：…
  l = l.replace(/^[-*]\s+/, "").replace(/^\d+[.)]\s+/, "").replace(/^>\s?/, "")
  var m = /^([\u4e00-\u9fffA-Za-z][\u4e00-\u9fffA-Za-z0-9_\-·]{0,14}?)[:：]\s*(.+)$/.exec(l)
  if (!m) return null
  var name = m[1]
  var rest = m[2].trim()
  if (!rest) return null
  // 去掉"X说/X问道…"类引述词，名牌只留说话人名
  name = name.replace(/(说道|问道|答道|回答|笑着说|大声说|低声说|喃喃道|叹道|笑道|叫道|喊道|说|问|答)$/, "")
  if (!name) return null
  // 常见"标签：内容"结构（说明/注意/功能/优点…），说话人名不应命中这些词；
  // 允许带后缀的复合标签：第一段 / 注意事项 / 另一方面…
  if (/^(注意|提示|警告|说明|备注|例如|比如|总结|结论|结果|原因|功能|优点|缺点|用法|语法|示例|例子|步骤|参考|特点|方法|作用|定义|区别|来源|建议|补充|总之|综上|输出|错误|问题|答案|解决|方案|参数|返回值|环境|依赖|地址|链接|格式|详情|名称|状态|类型|数量|大小|版本|命令|路径|项目|文件|目录|用户|系统|模型|对话|消息|内容|时间|日期|标题|文档|教程|指南|默认|必须|表示|即|如下|如下所示|第一|第二|第三|第四|首先|其次|最后|接着|然后)(段|部分|章|节|点|条|项|步|个|种|方面|内容|情况|事项|说明|建议|提示)?[:：]/.test(name + "：")) {
    return null
  }
  // 说话内容特征：含引号，或以句末标点（。！？…!?）收尾
  if (/[「」『』"'“”]/.test(rest) || /[。！？…!?]$/.test(rest)) {
    return { name: name, rest: rest }
  }
  return null
}

/** 去掉整句外层的成对引号（「」『』“”""），气泡内展示更干净 */
function stripOuterQuotes(s) {
  var t = String(s).trim()
  if (t.length >= 2) {
    var a = t.charAt(0), b = t.charAt(t.length - 1)
    var pairs = ["「」", "『』", "“”", "\"\"", "''"]
    for (var i = 0; i < pairs.length; i++) {
      if (a === pairs[i].charAt(0) && b === pairs[i].charAt(1)) {
        return t.slice(1, -1).trim()
      }
    }
  }
  return t
}

/** 该行是否为"说话人：内容"结构 */
function isSpeakerLine(line) {
  return speakerParts(line) !== null
}

/**
 * isDialogueSegment(text) → bool
 * 一段（空行分隔）内 ≥2 句说话人冒号句，且至少含引号或 ≥2 句带句末标点，
 * 才认定为对话段——避免"功能：xxx\n优点：xxx"这种标签清单被误判。
 */
function isDialogueSegment(text) {
  var lines = String(text).split("\n")
  var hits = 0, quoted = 0, punct = 0
  for (var i = 0; i < lines.length; i++) {
    var sp = speakerParts(lines[i])
    if (!sp) continue
    hits++
    if (/[「」『』"'“”]/.test(sp.rest)) quoted++
    else if (/[。！？…!?]$/.test(sp.rest)) punct++
  }
  return hits >= 2 && (quoted >= 1 || punct >= 2)
}

/**
 * splitSegments(md) → [{ text, kind }]
 * 按空行把一条消息切成若干"段"（``` 代码块内部不切）；
 * kind: "dialogue"（对话段）| "narrative"（普通段）。
 * 含代码块的段一律视为普通段，避免对话渲染破坏代码排版。
 */
function splitSegments(md) {
  if (!md) return []
  var lines = String(md).replace(/\r\n/g, "\n").split("\n")
  var segs = [], cur = [], inFence = false, hasFence = false, first = true
  function flush() {
    if (!cur.length) return
    var text = cur.join("\n")
    var kind = (!hasFence && isDialogueSegment(text)) ? "dialogue" : "narrative"
    segs.push({ text: text, kind: kind, first: first })
    cur = []
    hasFence = false
    first = false
  }
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    if (/^```/.test(line.trim())) { inFence = !inFence; hasFence = true }
    if (!inFence && !line.trim()) { flush(); continue }
    cur.push(line)
  }
  flush()
  return segs
}

/**
 * dialogueGroups(text) → [{ kind: "group", name, texts[], side } | { kind: "plain", text }]
 * 对话段内的渲染单元：连续同说话人的行合并为一组气泡（texts 多行），
 * 组间按出现顺序左右交替（side: "left"|"right"）；非说话人行作为 plain 原样渲染。
 */
function dialogueGroups(text) {
  var lines = String(text).split("\n")
  var out = []
  var groupCount = 0
  for (var i = 0; i < lines.length; i++) {
    var sp = speakerParts(lines[i])
    if (sp) {
      var last = out.length ? out[out.length - 1] : null
      if (last && last.kind === "group" && last.name === sp.name) {
        last.texts.push(sp.rest)
      } else {
        out.push({
          kind: "group",
          name: sp.name,
          texts: [stripOuterQuotes(sp.rest)],
          side: groupCount++ % 2 === 0 ? "left" : "right",
        })
      }
    } else {
      var l = lines[i].trim()
      if (l) out.push({ kind: "plain", text: l })
    }
  }
  return out
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