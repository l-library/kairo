# M0 技术验证（spike）

用 PI SDK 验证 PLAN.md §9 M0 的三个关键能力，全部基于 kairo 独立
`agentDir`（`~/.config/kairo/agent`，由 `scripts/setup.sh` 导入）。

## 运行

```bash
npx tsx dev-m0/01-stream.ts
npx tsx dev-m0/02-tool-approval.ts
npx tsx dev-m0/03-modes.ts
```

## 三个演示

| 脚本 | 验证点 | 关键结论 |
|------|--------|----------|
| `01-stream.ts` | 建会话、流式文本事件链 | `message_update(text_delta)` 增量输出、`message_end` 汇总 |
| `02-tool-approval.ts` | 工具事件链 + `tool_call` 阻塞钩子 + diff | 只读放行；写工具挂起等审批；`generateDiffString` 双色 diff；批准后执行落盘 |
| `03-modes.ts` | 模式切换 | `setActiveToolsByName([])` 清空工具 → 0 次工具调用；7 工具恢复 → ls 触发 |

## 对 daemon 实现的关键结论

1. **内联扩展必须走 `resourceLoaderOptions.extensionFactories`**（`createAgentSessionServices`
   不接受 ResourceLoader 实例），且扩展在会话创建时随 `createAgentSessionFromServices` 自动绑定。
2. **`tool_call` 钩子先于工具执行**（在 `tool_execution_start` 之后），可 `await` 任意 Promise，
   返回 `{block: true, reason}` 阻断；批准后返回 `undefined` 放行。
3. **edit 入参是 `{path, edits:[{oldText,newText}]}`，path 可能是绝对或相对**；diff 计算须先
   把 edits 应用到旧内容再调 `generateDiffString`。
4. **`setActiveToolsByName` 同步生效**于 `agent.state.tools` 并重建系统提示；模型工具定义随
   之更新，行为级验证（chat 0 工具调用 / command 触发工具）最可靠。
5. `agent.state.tools` 是工具状态的唯一可靠事实源；系统提示文本无结构化工具章节，不可依赖。