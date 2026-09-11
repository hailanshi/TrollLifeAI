# TrollLifeAI · 单机文字人生重开模拟器

一个完全离线的 Flutter 文字人生模拟器：选年代、选城市、抽天赋，然后逐岁推进，
经历 155 条剧本事件，养宠物、谈恋爱、结婚生子、上班失业、创业破产、入狱出狱，
最后寿终正寝并转世重开。

## 一、环境要求

- Flutter **3.13 及以上**（Dart 3.x），推荐 Flutter 3.16+ 稳定版
- 只依赖官方 SDK 与 `provider: ^6.1.2`，无其他第三方包

```bash
flutter --version
```

## 二、第一次运行（重要）

本仓库**只包含 Dart 源码与资源**，刻意没有提交 `android/` `ios/` `web/` 等平台目录，
所以第一次运行前需要在工程根目录生成平台脚手架：

```bash
cd flutter_trolllifeai

# 生成平台目录（不会覆盖已有的 lib/ pubspec.yaml assets/）
flutter create .

# 拉取依赖
flutter pub get

# 运行
flutter run
```

> `flutter create .` 会依据工程名 `trolllifeai` 生成 Android / iOS 等目录。
> 如果它试图覆盖 `pubspec.yaml`，可用 `flutter create --platforms=android,ios .` 只生成平台目录。

## 三、目录结构

```
flutter_trolllifeai/
├─ pubspec.yaml
├─ analysis_options.yaml
├─ assets/json/            # 5 份只读剧本数据
│  ├─ talents.json         # 44 条天赋
│  ├─ achievements.json    # 74 个成就
│  ├─ skills.json          # 29 个技能
│  ├─ city.json            # 9 座城市
│  └─ event.json           # 155 条事件
└─ lib/
   ├─ main.dart
   ├─ theme/app_theme.dart
   ├─ models/              # 数据模型（fromJson / toJson 齐全）
   ├─ services/            # 数据加载 / 存档 / 事件引擎 / 主动行动 / 人生评分 / AI 剧情
   ├─ providers/           # GameProvider（ChangeNotifier）
   ├─ pages/               # 8 个页面（含 AI 剧情设置）
   └─ widgets/             # 可复用小组件（含 AI 等待层、评分面板、存档槽位面板）
```

## 四、玩法速览

| 阶段 | 操作 |
| --- | --- |
| 开局 | 选年代（80/90/00/10/20）→ 选城市 → 抽 3 选 1 天赋（可重抽 3 次） |
| 主界面 | 11 项属性、资产与负债、成瘾状态、人际关系、宠物、人生日志 |
| 推进 | 「过一年」逐年推进；「快进 10 年」连续推进（遇事件自动暂停） |
| 事件 | 弹窗展示剧情与选项，选择后自动结算属性、触发标记效果并关闭 |
| 结束 | 健康值 ≤0 或年龄 ≥ 寿命上限 → 人生总结 → 转世（继承 8% 单项属性） |

- 技能永久生效：命中事件关键词的技能每个 +7% 成功率，最高 +35%
- 罪恶值 ≥45 每年有概率被捕入狱，服刑期间跳过年份且没有收入
- 成瘾值 ≥60 每年有概率触发成瘾发作强制事件
- 成就跨轮回永久保存
- 金手指：主界面右上角「齿轮」→ 调试控制台，密码 **208526**

## 五、存档说明

存档由 `StorageService` 使用 `dart:io` 直接写文件，按以下顺序寻找可写目录：

1. 环境变量 `TROLLLIFE_HOME` 指定的目录
2. 应用目录内 `./.trolllife/`（移动端不可写时自动跳过）
3. 系统临时目录下的 `trolllife/`

任何一步失败都会**自动降级为内存存档**，界面会提示「本次进度仅保存在内存中」，
不会崩溃。存档文件为 `save.json`，成就文件为 `achievements.json`（与资源同名但位于存档目录）。

## 六、玩法增强（与网页版对齐）

| 模块 | 说明 |
| --- | --- |
| 主动行动 | 每岁 1 点行动力，共 14 种行动（加班赚钱 / 看病就医 / 健身锻炼 / 进修学习 / 社交应酬 / 投资理财 / 陪伴家人 / 休息放松 / 戒瘾治疗 / 相亲交友 / 生育子女 / 创业尝试 / 陪伴宠物 / 全面体检）；服刑期间行动力为 0，不可用行动会置灰并显示原因 |
| 关系互动 | 每人每年 1 次：送礼（¥2000）/ 深聊 / 和解（仇人）/ 求婚（恋人，成功转配偶并解锁「携手一生」） |
| 人生评分 | 年龄 + 属性加权 + 财富资产 + 人际 + 技能 + 成就 + 宠物 − 压力/成瘾/罪恶/负债；六档称号，轮回页与死亡结算弹窗都能看「评分明细」 |
| AI 剧情 | 可选的 OpenAI 兼容接口（默认 DeepSeek），按概率把本地事件换成 AI 原创剧情，带「AI 原创」标记；失败 / 超时 / 结构不合格一律回退本地剧情 |
| 存档管理 | 3 个槽位（保存 / 读取 / 删除）+ 存档文本导出与导入，放在轮回页（主页菜单也能打开） |

配置文件与存档同目录：

- `save.json` 主存档，`achievements.json` 成就，`slot_1.json`~`slot_3.json` 槽位
- `ai_config.json` AI 配置（含 API Key），**只在读取时使用，不会写进代码，也不会随存档导出**

## 七、测试与检查

```bash
flutter analyze
flutter test
```

## 八、已知限制

- 无 SDK 环境下无法编译验证，首次 `flutter pub get` 后如出现 API 变更提示，
  以 Flutter 稳定版 `flutter analyze` 的输出为准。
- 数值平衡（漂移速度、被捕概率、寿命区间）集中在 `lib/services/event_engine.dart`
  顶部的常量区，可直接调整。
