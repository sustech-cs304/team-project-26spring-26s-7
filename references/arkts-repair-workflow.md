# ArkTS 自动化修复工作流参考文档

**创建日期**: 2026-03-27
**最后更新**: 2026-03-27
**版本**: 1.0.0

---

## 目录

1. [概述](#概述)
2. [核心组件](#核心组件)
3. [配置清单](#配置清单)
4. [使用指南](#使用指南)
5. [工作流程图](#工作流程图)
6. [错误分类规则](#错误分类规则)
7. [日志检索](#日志检索)
8. [改进建议](#改进建议)
9. [故障排除](#故障排除)

---

## 概述

ArkTS 自动化修复工作流是一套专为 HarmonyOS 前端项目设计的闭环修复系统，通过以下机制实现自动化错误修复：

- **强制调用 MCP**: 在修改 ArkTS 代码时强制调用 `arkts-assistant` MCP
- **编译验证循环**: 每轮修复后自动执行 hvigor 构建验证
- **智能跳出**: 遇到需要结构性修改的错误时自动跳出循环
- **上下文压缩**: 保留最近 2 轮详情，归档完整历史到 memory
- **错误日志持久化**: 所有修复历史写入 `memory/arkts-repair-log.md` 供未来检索

---

## 核心组件

### 1. Slash 命令

| 命令 | 位置 | 功能 |
|------|------|------|
| `/arkts-fix` | `~/.claude/skills/arkts-fix/SKILL.md` | 执行自动化修复循环 |
| `/init-arkts-repair` | `~/.claude/skills/init-arkts-repair/SKILL.md` | 初始化修复环境 |

### 2. 配置文件

| 文件 | 位置 | 功能 |
|------|------|------|
| `settings.json` | `~/.claude/settings.json` | hvigor 命令白名单 |
| `CLAUDE.md` | `~/.claude/CLAUDE.md` | 全局工作流说明 |
| `CLAUDE.local.md` | `项目根目录/CLAUDE.local.md` | 项目级修复流程 |

### 3. 日志文件

| 文件 | 位置 | 功能 |
|------|------|------|
| `arkts-repair-log.md` | `memory/arkts-repair-log.md` | 修复历史记录 |

### 4. Hook 脚本

| 文件 | 位置 | 功能 |
|------|------|------|
| `arkts-repair-hook.js` | `~/.claude/hooks/arkts-repair-hook.js` | 构建命令自动授权和错误收集 |

### 5. MCP 服务器

| 名称 | 配置位置 | 功能 |
|------|------|------|
| `arkts-assistant` | `~/.claude/mcp.json` | ArkTS 代码分析和修复建议 |

---

## 配置清单

### settings.json 配置

```json
{
  "allowedCommands": [
    "hvigorw",
    "hvigorw.js",
    "powershell -Command *hvigorw*"
  ]
}
```

### mcp.json 配置

```json
{
  "mcpServers": {
    "arkts-assistant": {
      "type": "stdio",
      "command": "node",
      "args": ["C:/Users/ZZH/.claude/arkts-assistant/dist/index.js"],
      "env": {}
    }
  }
}
```

### 环境变量

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `ARKTS_REPAIR_MODE` | 启用修复循环模式 | `false` |
| `ARKTS_REPAIR_FILE` | 目标修复文件 | 当前打开文件 |
| `ARKTS_REPAIR_ROUND` | 当前修复轮次 | `1` |
| `ARKTS_REPAIR_MAX` | 最大修复轮次 | `10` |

---

## 使用指南

### 基本用法

```bash
# 执行修复循环
/arkts-fix

# 指定文件修复
/arkts-fix --file=feature/map-travel/components/MapTravelComponent.ets

# 自定义最大轮数
/arkts-fix --max-retries=5

# 初始化环境
/init-arkts-repair
```

### 完整工作流

```bash
# 步骤 1: 检测错误（通常在编译或 lint 后）
npm run lint  # 或使用 DevEco Studio 内置检查

# 步骤 2: 执行修复循环
/arkts-fix --file=<path/to/file.ets>

# 步骤 3: 查看修复结果
cat memory/arkts-repair-log.md

# 步骤 4: 如有需要，检索历史类似错误
grep -i "类型不匹配" memory/arkts-repair-log.md
```

---

## 工作流程图

```
┌─────────────────────────────────────────────────────────────────┐
│                    /arkts-fix 触发                               │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ Step 1: 执行快速语法检查 (lint)                                  │
│ - 识别所有 ArkTS 语法错误                                         │
│ - 输出错误列表和位置                                              │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ Step 2: 进入修复循环 (max 10 轮)                                  │
│ ┌───────────────────────────────────────────────────────────┐   │
│ │ 每轮迭代:                                                  │   │
│ │ 1. 调用 arkts-assistant MCP 分析当前错误                     │   │
│ │ 2. 生成修复方案并修改代码                                   │   │
│ │ 3. 执行快速 lint 检查                                        │   │
│ │    - 无错误 → 执行完整 hvigor 构建                           │   │
│ │    - 有错误 → 继续下一轮                                   │   │
│ │ 4. 记录修复日志到 memory/arkts-repair-log.md               │   │
│ └───────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ Step 3: 检查跳出条件                                             │
│ ├── ✅ 编译成功 → 结束                                          │
│ ├── ⚠️ 需要彻底实现项目细节 → 跳出并提示用户                       │
│ ├── ⚠️ 需要修改项目结构 → 跳出并提示用户                         │
│ ├── ⚠️ 需要删除文件/文件夹 → 跳出并提示用户                      │
│ └── ⚠️ 超过 10 轮 → 暂停并提示用户                                │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ Step 4: 上下文管理                                               │
│ - 保留最近 2 轮修复详情在上下文中                                  │
│ - 将完整历史写入 memory/arkts-repair-log.md                     │
│ - 使用 compact 策略继续工作 (如需要)                              │
└─────────────────────────────────────────────────────────────────┘
```

---

## 错误分类规则

### 局部修复 (继续循环)

以下错误类型可以通过局部修改修复，继续循环：

| 错误类型 | 示例 | 修复策略 |
|----------|------|----------|
| 语法错误 (SyntaxError) | 缺少分号、括号不匹配 | 直接修正语法 |
| 类型不匹配 (Type mismatch) | `string` 赋值给 `number` | 添加类型转换 |
| 未定义的变量/方法 | `variable is not defined` | 添加声明或导入 |
| 导入路径错误 | `Module not found` | 修正导入路径 |
| 简单的 API 使用错误 | 参数顺序错误 | 修正 API 调用 |

### 跳出循环 (需要人工介入)

#### 1. 需要彻底实现项目细节 ⚠️

- 缺少完整的数据模型
- 需要实现一个完整的 Service 层
- 需要添加新的 API 接口定义
- 需要实现复杂的业务逻辑

**示例**:
```
错误：Property 'userData' does not exist on type 'UserService'
跳出原因：UserService 类缺少 userData 属性的实现，需要完整实现该方法
```

#### 2. 需要修改项目结构 ⚠️

- 需要移动文件到新目录
- 需要重新组织模块结构
- 需要创建新的目录层级
- 需要修改 `build-profile.json5`

**示例**:
```
错误：Cannot resolve module '@/components/shared/Button'
跳出原因：项目使用 @ 别名但未配置，需要修改 tsconfig.json 或 build-profile.json5
```

#### 3. 需要删除文件/文件夹 ⚠️

- 文件内容完全错误需要重写
- 需要删除废弃的组件
- 需要清理整个目录

**示例**:
```
错误：Multiple conflicting exports in file
跳出原因：文件结构混乱，建议删除后重新创建
```

---

## 日志检索

### 常用检索命令

```bash
# 搜索特定错误类型
grep -i "类型不匹配" memory/arkts-repair-log.md
grep -i "import.*not found" memory/arkts-repair-log.md

# 查看最近 N 次修复记录
grep -B5 -A5 "Session #" memory/arkts-repair-log.md | tail -50

# 查找特定文件的修复历史
grep -n "feature/map-travel" memory/arkts-repair-log.md

# 查找成功的修复案例
grep -B10 "✅ 成功" memory/arkts-repair-log.md

# 查找跳出原因统计
grep "跳出原因:" memory/arkts-repair-log.md
```

### 检索场景示例

| 场景 | 命令 |
|------|------|
| 调试 MapTravelComponent 问题 | `grep -B5 -A5 "MapTravelComponent" memory/arkts-repair-log.md` |
| 查找所有类型错误修复 | `grep -i "type.*mismatch" memory/arkts-repair-log.md` |
| 查看最近失败的修复 | `grep -B10 "❌ 失败" memory/arkts-repair-log.md \| tail -30` |
| 统计跳出原因 | `grep "跳出原因:" memory/arkts-repair-log.md \| sort \| uniq -c` |

---

## 改进建议

### 短期改进 (1-2 周)

#### 1. 错误分类器增强

**现状**: 当前依赖 AI 判断错误类型，可能存在误判

**建议**:
- 创建错误模式库，基于正则表达式预分类
- 为常见错误类型建立修复模板
- 引入置信度评分，低置信度时主动询问用户

**实现示例**:
```javascript
const errorPatterns = {
  SYNTAX: [/SyntaxError/, /缺少分号/, /非法字符/],
  TYPE_MISMATCH: [/类型.*不匹配/, /type.*mismatch/],
  MODULE_NOT_FOUND: [/Module not found/, /无法解析模块/],
  STRUCTURAL: [/需要实现/, /未定义的服务/, /缺少接口/]
};

function classifyError(error) {
  for (const [type, patterns] of Object.entries(errorPatterns)) {
    if (patterns.some(p => p.test(error.message))) {
      return { type, confidence: 'high' };
    }
  }
  return { type: 'UNKNOWN', confidence: 'low' };
}
```

#### 2. 构建速度优化

**现状**: 每次完整构建耗时较长

**建议**:
- 实现增量构建检测，只编译修改的模块
- 添加快速检查模式（仅语法检查，不执行完整构建）
- 缓存之前的构建结果用于对比

#### 3. 日志可视化

**现状**: 日志为纯文本，难以快速浏览

**建议**:
- 添加 Markdown 表格汇总每次修复
- 生成修复统计图表（成功率、常见错误类型）
- 创建 Web 界面浏览修复历史

### 中期改进 (1-2 月)

#### 4. 多文件并行修复

**现状**: 每次只能修复一个文件的错误

**建议**:
- 分析错误依赖图，确定可并行修复的文件组
- 为独立错误创建多个修复分支
- 合并修复结果前进行冲突检测

#### 5. 修复质量评估

**现状**: 无修复质量评估机制

**建议**:
- 引入代码复杂度评分，确保修复不增加复杂度
- 检查修复后的代码风格一致性
- 为关键组件添加回归测试

#### 6. 上下文压缩优化

**现状**: 固定保留 2 轮，可能不够或过多

**建议**:
- 基于错误相关性动态决定保留轮数
- 引入语义相似度计算，合并相似修复历史
- 使用向量数据库存储修复历史用于语义检索

### 长期改进 (3-6 月)

#### 7. 机器学习模型训练

**建议**:
- 收集修复历史数据集
- 训练错误分类模型
- 训练修复方案推荐模型
- 建立修复成功率预测

#### 8. 集成到 CI/CD

**建议**:
- 在 PR 检查中自动运行修复循环
- 设置修复成功率阈值，低于阈值时 blocking
- 自动创建修复建议评论

#### 9. 跨项目知识共享

**建议**:
- 建立组织级的 arkts-repair-log 数据库
- 支持跨项目检索类似错误
- 建立最佳实践库

---

## 故障排除

### 常见问题

#### 1. hvigor 构建命令执行失败

**症状**:
```
ERROR: Cannot run program "hvigorw": error=2, No such file or directory
```

**解决方案**:
```bash
# 确认 DevEco Studio 安装路径
ls "C:/Apps/DevEco Studio/tools/hvigor/bin/hvigorw.js"

# 如路径不同，更新 settings.json 中的命令路径
# 或使用绝对路径执行
powershell -Command "& '<完整路径>/hvigorw.js' ..."
```

#### 2. arkts-assistant MCP 未响应

**症状**:
```
Error: MCP server "arkts-assistant" did not respond
```

**解决方案**:
```bash
# 检查 MCP 配置
cat ~/.claude/mcp.json

# 确认 arkts-assistant 已正确安装
ls ~/.claude/arkts-assistant/dist/index.js

# 重启 Claude Code 会话
```

#### 3. 修复循环无法跳出

**症状**: 超过 10 轮后仍然继续

**解决方案**:
- 检查跳出条件判断逻辑
- 手动中止并检查错误类型
- 增加更明确的跳出信号（如特定注释标记）

#### 4. 日志文件未更新

**症状**: `memory/arkts-repair-log.md` 没有新记录

**解决方案**:
```bash
# 检查文件权限
ls -l memory/arkts-repair-log.md

# 检查日志写入路径是否正确
# 检查 hook 脚本是否正常执行
node ~/.claude/hooks/arkts-repair-hook.js --test
```

### 性能调优

#### 构建速度优化

```bash
# 启用增量构建
-p incremental=true

# 使用 daemon 模式
--daemon

# 限制并行度（如内存不足）
--parallel=2

# 禁用不必要的分析
--analyze=none
```

#### 上下文管理

```javascript
// 在修复循环中定期清理上下文
if (round > 2) {
  // 归档早期历史
  archiveToLog(round - 2);
  // 仅保留最近 2 轮详情
  keepDetails(round - 1, round);
}
```

---

## 附录

### A. 文件结构总览

```
~/.claude/
├── settings.json              # 命令白名单配置
├── CLAUDE.md                  # 全局工作流说明
├── mcp.json                   # MCP 服务器配置
├── skills/
│   ├── arkts-fix/
│   │   └── SKILL.md          # /arkts-fix 命令定义
│   └── init-arkts-repair/
│       └── SKILL.md          # /init-arkts-repair 命令定义
└── hooks/
    └── arkts-repair-hook.js   # 构建钩子

project/base/
├── CLAUDE.local.md            # 项目级配置
└── memory/
    └── arkts-repair-log.md    # 修复历史日志
```

### B. 版本历史

| 版本 | 日期 | 变更内容 |
|------|------|----------|
| 1.0.0 | 2026-03-27 | 初始版本，包含核心修复循环功能 |

### C. 相关链接

- [ArkTS 官方文档](https://developer.harmonyos.com/cn/docs/documentation/doc-guides-V1/arkts-get-started-0000001705361205-V1)
- [DevEco Studio 用户指南](https://developer.harmonyos.com/cn/docs/documentation/doc-references-V3/ide-0000001478053669-V3)
- [hvigor 构建工具文档](https://developer.harmonyos.com/cn/docs/documentation/doc-references-V3/hvigor-0000001493574432-V3)
