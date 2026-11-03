# FFlow 桌面隐藏式 GUI 图形生成与 PNG 导出引擎开发计划

> 文档版本：1.1\
> 编制日期：2026-11-03\
> 项目基础：[`risol/FFlow`](https://github.com/risol/FFlow)\
> 目标形态：运行在已有桌面 GUI 环境中，保留 Flutter / FFlow
> 渲染体系；渲染窗口或渲染视图在后台隐藏，不向最终用户展示。

------------------------------------------------------------------------

## 1. 项目目标

基于现有 FFlow Flutter
SDK，开发一个运行在桌面应用环境中的图形生成与导出模块。系统接收结构化文件或文本，解析业务语义，转换为统一图模型，自动布局，调用
FFlow
的节点、连线和画布渲染能力，在**不向用户展示渲染窗口或编辑界面**的情况下生成
PNG 图片，并可选择导出标准化 JSON 图形数据。桌面系统本身具备正常 GUI /
Windowing 环境；本项目不面向 Linux Server、Docker 或无桌面服务器部署。

本项目不是纯 Dart 绘图库，也不是对 FFlow
编辑器进行鼠标自动化操作。目标是复用 FFlow 的 Flutter
Widget、Canvas、Painter、Node、Edge
和布局能力，增加一个桌面隐藏式渲染宿主（Desktop Hidden Rendering
Host）及输入格式适配层。

### 1.1 目标工作流

``` text
输入文件 / 文本
  ├─ FFlow JSON
  ├─ 通用 Graph JSON
  ├─ SQL DDL
  ├─ Mermaid Flowchart
  └─ 后续：DBML / BPMN
        │
        ▼
格式解析与语义转换
        │
        ▼
统一 DiagramDocument 图模型
        │
        ▼
FFlow Node / Edge 适配
        │
        ▼
自动布局与画布尺寸计算
        │
        ▼
隐藏式 Flutter / FFlow 渲染宿主
        │
        ▼
完整画布截图 / PNG 编码
        │
        ├─ PNG 文件
        └─ 可选：FFlow JSON / 标准 Graph JSON
```

### 1.2 核心验收目标

1.  在目标桌面操作系统的正常 GUI
    会话中，自动完成导入、解析、布局、渲染和导出。
2.  渲染过程使用 Flutter / FFlow 的真实 Widget、Canvas 和 Painter
    渲染链路，但不向最终用户展示渲染窗口或编辑器界面。
3.  能够将 FFlow 自身 JSON 快照恢复为图形。
4.  能够从通用 JSON、SQL DDL 和 Mermaid Flowchart 生成 ER 图或流程图。
5.  PNG 必须覆盖完整图形，而不是只截取当前屏幕可视区域。
6.  提供可被桌面宿主应用直接调用的 Dart 渲染服务 API；CLI
    仅作为开发调试和自动化测试工具，不作为必须交付的服务端产品。
7.  输入错误、渲染失败、超大图和资源不足时，能够返回明确错误，不产生静默损坏的图片。
8.  不要求部署 Docker、Linux Server、HTTP 服务或虚拟显示服务器。

## 2. 当前 FFlow 能力盘点

根据当前仓库 README、源码和 example 检查，FFlow 已有以下基础能力。

  能力                                当前状态         对本项目的意义
  ----------------------------------- ---------------- ----------------------------------
  Node / Edge 图模型                  已有             可作为图形渲染的数据基础
  自定义 Node Widget                  已有             可实现 ER 表、流程节点等业务外观
  自定义 Edge / Edge 样式             已有             可实现关系线、流程连线和标签
  `FlowGraphSnapshot.toJson()`        已有             可序列化图形快照
  `FlowGraphSnapshot.fromJson()`      已有             可恢复 FFlow 图形快照
  `FlowGraphSnapshot.migrateJson()`   已有             已有快照 Schema 迁移入口
  `FlowLayeredLayoutEngine`           已有             可进行分层有向布局
  `FlowForceLayoutEngine`             已有             可作为力导向布局基础
  `FlowGraphController`               已有             管理图形状态
  `FFlowCanvas`                       已有             核心画布渲染组件
  PNG 导出服务                        未发现现成实现   需要新增
  SQL / DBML 解析器                   未发现           需要新增
  Mermaid 解析器                      未发现           需要新增
  ER / BPMN 业务语义                  未内置           需要在业务层建模
  隐藏式渲染宿主                      未发现完整实现   本项目关键研发内容

### 2.1 关键源码位置

-   `lib/fflow.dart`：SDK 公共导出入口。
-   `lib/src/models/flow_node.dart`：节点模型。
-   `lib/src/models/flow_edge.dart`：连线模型。
-   `lib/src/models/flow_graph_snapshot.dart`：图形 JSON
    快照序列化、反序列化和迁移。
-   `lib/src/controllers/flow_graph_controller.dart`：图状态控制器。
-   `lib/src/interactions/flow_layered_layout.dart`：分层布局。
-   `lib/src/interactions/flow_force_layout.dart`：力导向布局。
-   `lib/src/canvas/flow_canvas.dart`：画布组件。
-   `example/lib/screens/flow_editor_screen.dart`：现有示例的 JSON
    导入、导出和布局调用示例。

现有 example 已经演示了 FFlow JSON 快照的粘贴导入、JSON
文本导出和自动布局，但这不等于已经具备任意业务格式解析或 PNG
文件导出能力。

------------------------------------------------------------------------

## 3. 范围与非目标

### 3.1 第一阶段必须实现

-   FFlow JSON 快照导入。
-   通用 Graph JSON 导入。
-   SQL DDL 转 ER 图。
-   Mermaid Flowchart 转流程图。
-   统一图模型和 FFlow 模型适配。
-   自动布局。
-   桌面环境下的隐藏式 Flutter / FFlow 渲染。
-   完整画布 PNG 导出。
-   可供桌面宿主应用调用的 Dart API。
-   可选的本地 CLI 调试入口。
-   单元测试、渲染 Golden Test 和桌面端到端测试。

### 3.2 后续扩展

-   DBML 导入。
-   BPMN 2.0 XML 导入。
-   更多 SQL 方言。
-   SVG / PDF 导出。
-   桌面应用内部的批量任务队列。
-   图形主题、模板和用户自定义节点。
-   大型图形的分块渲染或超大图片导出。
-   如果未来确有跨进程调用需求，再单独评估 IPC；不预设 HTTP Server。

### 3.3 明确不做

-   不开发面向最终用户的可视化编辑器产品。
-   不要求用户打开渲染窗口、拖动节点或点击导出。
-   不通过屏幕坐标、鼠标模拟或 UI 自动化完成任务。
-   不承诺任意 JSON 都能自动推断出 ER 图或流程图语义。
-   不在第一阶段实现完整 BPMN 规范。
-   不开发 Linux Server、Docker、容器化部署或虚拟显示环境。
-   不为了隐藏窗口而引入 Xvfb 或自定义 Flutter
    Embedder，除非目标桌面平台验证后证明确有必要。

## 4. 总体架构

建议采用分层架构，各层职责明确。渲染模块由现有桌面宿主应用或独立 Flutter
Desktop Host 调用；不增加服务端部署层，也不把 SQL、Mermaid
解析逻辑直接塞进 FFlow SDK。

``` text
┌─────────────────────────────────────────────────────┐
│             Desktop Host Application               │
│        桌面宿主调用、参数校验、任务生命周期管理        │
└──────────────────────────┬──────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────┐
│                Input Adapter Layer                  │
│ FFlow JSON │ Graph JSON │ SQL DDL │ Mermaid │ ...   │
└──────────────────────────┬──────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────┐
│                 Diagram Domain Layer                │
│ DiagramDocument / DiagramNode / DiagramEdge         │
│ ER Schema / Flowchart Semantics / Validation        │
└──────────────────────────┬──────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────┐
│                 FFlow Adapter Layer                 │
│ Domain Node → FlowNode                              │
│ Domain Edge → FlowEdge                              │
│ Layout Profile / Theme / Canvas Bounds              │
└──────────────────────────┬──────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────┐
│               Hidden Rendering Host                 │
│ Flutter Binding / Widget Tree / FFlowCanvas         │
│ RepaintBoundary / Render Pipeline                   │
└──────────────────────────┬──────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────┐
│                   Export Layer                      │
│ PNG Encoder │ JSON Serializer │ File Writer        │
└─────────────────────────────────────────────────────┘
```

### 4.1 输入适配层

每种输入格式实现独立 Parser / Adapter，输出统一的
`DiagramDocument`。解析器不直接创建 Flutter Widget，也不依赖 Flutter
`BuildContext`。

### 4.2 统一领域模型

建议新增独立的领域模型，不直接把 `FlowGraphSnapshot`
当作所有格式的唯一中间格式。FFlow Snapshot 面向 FFlow 图形状态，而
SQL、Mermaid、BPMN 有自己的领域语义。

建议模型：

``` dart
class DiagramDocument {
  final int schemaVersion;
  final DiagramType type; // er, flowchart
  final String? title;
  final Map<String, Object?> metadata;
  final List<DiagramNode> nodes;
  final List<DiagramEdge> edges;
  final DiagramLayoutConfig layout;
  final DiagramTheme theme;
}

class DiagramNode {
  final String id;
  final String type;
  final String label;
  final Map<String, Object?> data;
  final DiagramPosition? position;
  final DiagramSize? size;
  final List<DiagramPort> ports;
  final Map<String, Object?> style;
}

class DiagramEdge {
  final String id;
  final String source;
  final String target;
  final String? sourcePort;
  final String? targetPort;
  final String? label;
  final Map<String, Object?> data;
  final Map<String, Object?> style;
}
```

以上是逻辑结构示意，实际实现时需要使用不可变数据结构、明确的枚举和严格的
JSON Schema 校验。

### 4.3 FFlow 适配层

负责把领域模型转换为：

-   `FlowNode<DiagramNodeData>`
-   `FlowEdge`
-   FFlow 节点 Builder / Edge Renderer
-   FFlow 布局引擎所需的输入
-   `FlowGraphSnapshot`（用于保存 FFlow 原生快照）

位置、尺寸和业务数据的映射必须有明确规则。输入数据中没有位置时，由布局层计算；已有人工指定位置时，应支持保留位置或按配置重新布局。

### 4.4 渲染宿主

新增独立 Flutter
渲染入口，不复用整个示例编辑器页面。渲染宿主只加载渲染所需组件，不加载节点工具栏、属性面板、菜单、快捷键提示等编辑器
UI。

建议目录：

``` text
packages/
  diagram_domain/
  diagram_parsers/
  fflow_diagram_adapter/
  fflow_render_host/
apps/
  diagram_cli/
  diagram_server/          # 后续
```

如果当前仓库暂不适合拆成多个 Dart package，可以先放在独立的 `tool/` 或
`lib/src/` 子模块中，待接口稳定后再拆包。渲染 Host
应由桌面宿主直接集成，不要把核心能力长期塞进 example 页面。

------------------------------------------------------------------------

## 5. 隐藏式 GUI 渲染方案

这是整个项目的首要技术风险，也是第一个必须完成的 PoC。

### 5.1 目标定义

-   Flutter Engine 正常初始化。
-   Flutter Widget Tree 正常构建。
-   FFlow Canvas 正常执行布局和 Paint。
-   渲染结果不显示给最终用户。
-   渲染结果可以被捕获为完整 PNG。
-   一次进程可连续处理多个任务，或按任务启动独立进程。

"隐藏 GUI"不等同于把 Widget 放进 `Offstage`
后就能截图。`Offstage`、`Visibility(visible: false)`
等方式可能跳过布局或绘制，不应直接作为渲染实现。需要保持目标渲染子树参与真实布局和
Paint，再通过隐藏窗口或离屏 Surface 避免用户看到窗口。

### 5.2 桌面环境下需要验证的渲染方式

本项目运行在有正常 GUI / Windowing 环境的桌面系统中，因此优先复用桌面
Flutter Engine 和 FFlow Canvas，不建设虚拟显示服务器。

  ---------------------------------------------------------------------------------------------------------------------------------------------------------------------
  路线                     说明                                                   优点                                   风险 / 成本
  ------------------------ ------------------------------------------------------ -------------------------------------- ----------------------------------------------
  A.                       在现有 Flutter Desktop                                 不额外启动第二个应用；容易复用宿主的   必须验证隐藏状态下 RenderObject
  桌面宿主内隐藏渲染视图   应用中创建独立渲染子树或隐藏渲染区域，保持其参与真实   Flutter Engine                         仍完成布局和绘制；不能简单用 `Offstage`
                           Layout / Paint，再通过 `RepaintBoundary` 捕获                                                 跳过绘制

  B. 独立隐藏 Flutter      启动独立 Flutter Desktop                               与现有 FFlow                           需验证目标 OS
  Desktop Window           渲染窗口，窗口不向用户展示，但 Engine 正常构建 Widget  示例隔离，渲染生命周期较清晰           对隐藏窗口的帧调度、窗口可见性和资源释放行为
                           并执行 Paint                                                                                  

  C. 自定义离屏 Flutter    在需要完全脱离窗口管理器时，自定义 Engine / RenderView 控制力最高                             工程复杂度高；不是第一阶段默认方案
  Engine / Surface         / Surface                                                                                     
  ---------------------------------------------------------------------------------------------------------------------------------------------------------------------

**建议优先验证 A，再验证 B。** 如果宿主应用本身就是 Flutter
Desktop，优先在同一个 Engine 内建立隐藏渲染视图；如果宿主不是
Flutter，或需要隔离 Engine，再采用独立隐藏 Flutter Desktop Window。只有
A / B 都无法满足目标时，才评估 C。

重要约束：

-   不把渲染子树简单放进 `Offstage` 或 `Visibility(visible: false)`
    后就假设可以截图；这类组件可能跳过绘制。
-   不以"窗口最小化"作为隐藏渲染的唯一实现；操作系统可能暂停或降低不可见窗口的帧调度。
-   隐藏视图必须真实完成布局和 Paint，捕获结果必须来自实际 FFlow
    Canvas。
-   具体实现以目标桌面操作系统和宿主架构的 PoC 结果为准。

### 5.3 PNG 捕获技术路径

优先验证 Flutter 的 `RepaintBoundary` 截图方式：

``` dart
final boundary = repaintKey.currentContext!
    .findRenderObject() as RenderRepaintBoundary;

final image = await boundary.toImage(pixelRatio: 2.0);

final byteData = await image.toByteData(
  format: ui.ImageByteFormat.png,
);

final pngBytes = byteData!.buffer.asUint8List();
```

这是实现方向示例，不是完整生产代码。生产实现必须补齐：

-   `GlobalKey` 生命周期和 RenderObject 类型检查。
-   首帧完成、布局完成和 Paint 完成的等待机制。
-   `toImage()` 失败处理和超时。
-   `ui.Image.dispose()` 等资源释放。
-   `ByteData` 为空时的错误处理。
-   输出目录、文件写入和原子替换。
-   多任务连续运行时的内存回收与状态隔离。

### 5.4 完整画布而非视口截图

必须解决图形范围大于窗口的问题。

建议渲染流程：

1.  从所有节点的实际尺寸和位置计算 Graph Bounds。
2.  叠加标题区、边缘标签、连线控制点和安全留白。
3.  根据目标图片尺寸和最大像素限制计算逻辑画布尺寸及缩放。
4.  创建与导出尺寸匹配的渲染区域。
5.  将 FFlow Viewport 定位到完整 Graph Bounds。
6.  确保所有需要导出的节点和边都参与渲染。
7.  执行布局、等待稳定帧，再捕获 PNG。

不能只调用当前窗口的截图方法就认为实现了全图导出。FFlow
的可视区域裁剪能力（例如
`onlyRenderVisibleElements`）必须在完整图形渲染时正确配置；可选择关闭裁剪，或将视口范围设置为覆盖全部节点和边。

### 5.5 像素、尺寸和内存策略

-   `pixelRatio` 可配置，默认建议 2.0；高清导出可用 3.0。
-   逻辑画布尺寸和最终像素尺寸必须分别记录。
-   设置最大宽度、最大高度、最大总像素数和最大文件大小。
-   超出限制时返回明确错误，或启用分块渲染策略。
-   大图分块渲染属于后续增强，第一阶段先明确限制并拒绝超限任务。
-   默认使用固定背景色；可选透明背景，但需验证所有节点和 Painter
    对透明背景的兼容性。

### 5.6 字体和资源

-   容器内安装并固定所需字体，尤其是中文字体。
-   运行时不要依赖外部网络加载字体或图片。
-   字体必须在截图前加载完成。
-   Golden Test 和生产镜像使用相同字体版本。
-   记录 Flutter
    SDK、操作系统、字体包和渲染后端版本，降低不同环境的图片差异。

------------------------------------------------------------------------

## 6. 输入格式与解析范围

### 6.1 FFlow JSON

用途：恢复已经由 FFlow 创建的图形。

实现要求：

-   使用 `FlowGraphSnapshot.fromJson()`。
-   对节点业务数据实现 `decodeNodeData`。
-   对不兼容 Schema 版本返回清晰错误。
-   保留节点位置、尺寸、端口、父子分组、连线样式和视口数据。
-   支持 FFlow Snapshot 迁移入口。
-   导出时调用 `FlowGraphSnapshot.toJson()`，并实现对应的
    `encodeNodeData`。
-   对 JSON 顶层附加的业务元数据采用明确命名空间，避免与 FFlow
    保留字段冲突。

验收：从 FFlow JSON
导入后再导出，节点、连线和关键属性一致；允许忽略运行时临时状态，但必须在文档中明确。

### 6.2 通用 Graph JSON

建议定义项目自己的 `DiagramDocument` JSON Schema，至少包括：

-   `schemaVersion`
-   `diagramType`
-   `title`
-   `nodes`
-   `edges`
-   `layout`
-   `theme`
-   `metadata`

要求：

-   节点 ID 唯一。
-   Edge 的 source / target 必须引用存在的节点。
-   坐标、尺寸、样式字段必须校验类型和范围。
-   未知字段可按兼容策略保留在 `metadata`，不能默默丢弃关键业务数据。
-   支持显式指定节点类型、端口、关系类型和样式。
-   如果输入是普通业务 JSON（例如订单、用户、商品列表），必须通过
    Mapping Config 指定如何抽取节点和关系；不能承诺自动理解所有 JSON
    结构。

### 6.3 SQL DDL → ER 图

第一阶段建议先支持一种主力方言（优先 PostgreSQL），再按 Parser Adapter
扩展 MySQL、SQLite 等方言。方言支持范围必须在 CLI 帮助和文档中明确。

首批解析对象：

-   `CREATE TABLE`
-   列名、数据类型、可空性、默认值
-   主键（单列 / 复合主键）
-   外键（单列 / 复合外键）
-   `UNIQUE` 约束
-   表级约束
-   Schema / 命名空间（所选方言支持时）

后续增强：

-   Index / Partial Index
-   `COMMENT ON` / 列注释
-   Check Constraint
-   Enum / Domain
-   View
-   引用表缺失时的 dangling reference 诊断
-   更多数据库方言和复杂 DDL 语法

ER 领域模型至少需要表达：

-   Table：表名、Schema、说明。
-   Column：名称、类型、长度、可空、默认值、主键、唯一性。
-   Relationship：引用表、被引用表、字段映射、基数、可选性。
-   Constraint：约束名称和类型。

ER 图样式要求：

-   每张表渲染为一个自定义 Node。
-   表头显示表名，可显示 Schema。
-   表体按顺序显示字段、类型和关键约束标识。
-   主键、外键、唯一键应有清晰视觉区分。
-   关系线显示关系基数；需要支持 Crow's Foot（乌鸦脚）符号时，开发专用
    Edge Renderer，不能只依赖普通箭头代替。
-   复合外键应保留字段对应关系，必要时通过 Edge Label 或关系详情呈现。
-   表数量较多时，提供按 Schema 分组或主题分组的布局策略。

### 6.4 Mermaid Flowchart → 流程图

第一阶段限定 Mermaid `flowchart` / `graph` 子集，不宣称支持 Mermaid
全部图种。

首批支持：

-   `flowchart LR / RL / TB / BT`
-   常见节点 ID 和文本标签
-   矩形、圆角、圆形、菱形等常见节点形状
-   有向连线和无向连线（按语法支持情况）
-   连线标签
-   常见的节点声明与连接声明
-   重复声明节点的合并规则

后续增强：

-   `subgraph`
-   样式 class、主题变量
-   点击事件（默认不执行）
-   链接和图标
-   sequenceDiagram、classDiagram 等其他 Mermaid 图种（单独立项）

实现要求：

-   使用词法 /
    语法解析器或可靠的现有解析库，不建议用一组正则表达式处理全部语法。
-   语法错误需要返回行号、列号和错误上下文。
-   保留原始节点 ID，确保 Edge 引用稳定。
-   将 Mermaid 方向映射到 FFlow Layout Direction。
-   条件分支节点应渲染为菱形，连线标签显示分支条件。

### 6.5 DBML / BPMN

放入第二阶段。DBML 重点复用 ER 领域模型；BPMN
需要独立的流程语义映射，至少涉及 Event、Task、Gateway、Sequence
Flow、Pool / Lane 等概念。不要把 BPMN XML
直接粗略映射为普通矩形和箭头后就宣称完整支持。

------------------------------------------------------------------------

## 7. 图形布局与视觉规范

### 7.1 布局策略

  -------------------------------------------------------------------------------
  图形类型             首选布局                    说明
  -------------------- --------------------------- ------------------------------
  普通有向流程图       `FlowLayeredLayoutEngine`   按依赖方向分层

  循环流程 /           分层布局并处理 SCC          需要测试循环边路由
  强连通流程                                       

  ER 图                `FlowForceLayoutEngine` 或  关系网络常有环，不应盲目使用
                       ER 专用布局                 DAG 假设

  分组图               分层 / 力导向 + Parent      保留分组边界和内部布局
                       Group                       
  -------------------------------------------------------------------------------

FFlow 已有 `FlowLayeredLayoutEngine` 和
`FlowForceLayoutEngine`，应先验证它们在真实 ER /
流程数据上的效果。对于交叉边、复杂分组和大图，如果内置布局质量不足，再通过
FFlow 的布局适配接口接入 Dagre / ELK 等实现。

### 7.2 布局参数

所有布局参数应通过配置传入，不要硬编码在 Node Builder 中：

-   方向：LR / RL / TB / BT。
-   同层节点间距。
-   层间距。
-   Group Padding。
-   节点最小 / 最大尺寸。
-   边路由类型。
-   节点排序规则。
-   是否保留输入坐标。
-   是否自动适配画布。
-   画布边距。

### 7.3 视觉主题

至少提供：

-   `light`：白色背景、浅色节点。
-   `dark`：深色背景、深色节点。
-   `print`：高对比度、适合打印和文档插入。

主题必须统一控制节点、字段、关系线、箭头、标签、网格、背景和字体。第一阶段优先保证
light / print 的可读性。

### 7.4 文本排版

-   中文、英文、数字混排。
-   长表名和长字段名换行或截断策略。
-   数据类型对齐。
-   字段数量较多时节点高度自动扩展。
-   Edge Label 避免与节点、其他连线重叠。
-   导出图片不得出现字体缺失方框或文本裁切。

------------------------------------------------------------------------

## 8. PNG 导出接口设计

### 8.1 桌面宿主调用接口

桌面宿主不需要通过 HTTP 或外部服务提交任务，直接调用 Dart
渲染服务即可。建议 API：

``` dart
abstract interface class DiagramRenderService {
  Future<RenderResult> render({
    required DiagramInput input,
    required RenderOptions options,
  });
}

class RenderOptions {
  final double pixelRatio;
  final String theme;
  final String? layout;
  final String? direction;
  final int? maxWidth;
  final int? maxHeight;
  final bool transparentBackground;
}

class RenderResult {
  final Uint8List pngBytes;
  final int pixelWidth;
  final int pixelHeight;
  final Duration elapsed;
  final Map<String, Object?> diagnostics;
}
```

`DiagramInput` 可以是文件路径、原始文本或已解析的
`DiagramDocument`。建议渲染服务返回 PNG
字节和元数据，由宿主决定保存位置、文件命名和后续展示方式。

### 8.2 宿主集成方式

-   如果宿主本身是 Flutter Desktop，优先在同一个 Flutter Engine
    内集成隐藏渲染视图。
-   如果宿主不是 Flutter，使用独立 Flutter Desktop
    渲染进程，通过本地进程通信或平台通道传递输入与 PNG
    字节；是否采用独立进程由目标桌面架构决定。
-   不引入 HTTP Server、远程任务队列或云端文件存储。
-   如果只需单次或低频生成，直接调用 `render()`
    即可；如果需要批量生成，在宿主内部排队串行执行。

### 8.3 完整图形范围

渲染服务必须根据布局后的节点 Bounds 计算最终画布。Bounds 还要考虑：

-   节点阴影、描边和圆角外扩。
-   Edge 控制点和曲线路径外扩。
-   Edge Label。
-   图标题、图例和说明。
-   画布安全边距。

最终导出图片必须保证任何节点或标签都不被边界裁切。

## 9. 桌面应用集成与本地任务管理

本项目部署在桌面 GUI 环境中，由桌面宿主应用直接调用渲染模块。没有 Linux
Server、Docker、HTTP 服务或远程任务队列的交付要求。

### 9.1 首选：Dart 渲染服务 API

桌面宿主通过 Dart API 提交输入和渲染选项，获取 PNG
字节及渲染元数据。建议接口：

``` dart
abstract interface class DiagramRenderService {
  Future<RenderResult> render({
    required DiagramInput input,
    required RenderOptions options,
  });
}
```

`DiagramInput` 可包含文件路径、原始文本或已经解析的
`DiagramDocument`。输入解析、布局和渲染的职责应保持分离，便于单元测试和后续扩展。

### 9.2 桌面任务生命周期

建议每个任务按以下步骤执行：

1.  接收桌面宿主传入的输入和选项。
2.  校验输入格式和资源限制。
3.  解析为统一 `DiagramDocument`。
4.  转换为 FFlow Nodes / Edges。
5.  执行自动布局并计算完整画布边界。
6.  将图形提交到隐藏渲染视图。
7.  等待 Layout / Paint 完成。
8.  捕获 PNG 并编码。
9.  将 PNG 字节或输出文件路径返回给宿主。
10. 释放任务级 Controller、Key、Image 和临时资源。

首期建议在一个 Flutter Engine
内串行执行渲染任务，避免多个任务同时操作同一棵 Widget Tree 或共享 Canvas
状态。完成稳定性测试后，再评估多个独立隐藏渲染视图或多个 Engine
的并发能力。

### 9.3 可选：本地 CLI 调试工具

CLI 不是产品部署形态，只用于开发调试、批量 Fixture 测试和问题复现。CLI
应复用同一个
`DiagramRenderService`，不得复制一套独立的解析、布局或渲染实现。

示例：

``` bash
dart run tool/diagram_render.dart \
  --input ./schema.sql \
  --type er \
  --output ./schema-er.png \
  --layout force \
  --theme light \
  --scale 2
```

是否保留 CLI 取决于开发团队的测试与自动化需要，不影响桌面宿主 API
的设计。

### 9.4 桌面平台策略

-   先明确产品实际运行的桌面操作系统，再以该平台作为 Phase 0
    的首要验证目标。
-   FFlow 仓库当前 README 声明 Windows 和 Linux 示例构建已验证；macOS
    Runner 已包含但尚未验证。
-   如果产品需要 Windows，优先验证 Windows Flutter Desktop Host。
-   如果产品需要 macOS，先完成 macOS Runner / Engine / 隐藏窗口
    PoC，再承诺支持。
-   如果产品需要 Linux 桌面，则在正常桌面会话（X11 /
    Wayland）下验证，不以 Linux Server 或 Docker 为目标。
-   Android / iOS 不在本项目当前范围内。

## 10. 可靠性、安全与可观测性

### 10.1 输入安全

-   限制输入文件大小、JSON 深度、节点数、边数和字符串长度。
-   SQL 解析只处理 DDL 文本，不连接数据库、不执行 SQL。
-   Mermaid / DBML / BPMN 内容只解析，不执行脚本或事件。
-   不允许解析器触发任意文件读取或网络访问。
-   对未知字段、非法引用、循环引用和超大嵌套结构返回诊断信息。
-   对输出路径做规范化，阻止路径穿越。

### 10.2 渲染安全

-   限制最大节点数、边数、逻辑尺寸、像素尺寸和导出字节数。
-   单任务设置超时和内存上限。
-   避免渲染过程加载任意远程图片、字体或资源。
-   每个任务使用独立 Graph State，任务完成后清理 Controller、Key、Image
    和临时文件。
-   若 Flutter Engine
    无法安全重置任务状态，采用独立渲染视图或独立桌面渲染进程隔离；不引入服务端
    Worker 部署。

### 10.3 错误模型

建议统一错误码：

  错误码                    含义
  ------------------------- --------------------------------
  `INPUT_NOT_FOUND`         输入文件不存在
  `INPUT_TOO_LARGE`         输入文件超过限制
  `UNSUPPORTED_FORMAT`      不支持的输入格式
  `PARSE_ERROR`             语法或格式解析失败
  `SCHEMA_ERROR`            JSON Schema / 领域模型校验失败
  `GRAPH_REFERENCE_ERROR`   Edge 引用不存在的节点
  `LAYOUT_ERROR`            布局计算失败
  `RENDER_INIT_ERROR`       Flutter / 渲染宿主初始化失败
  `RENDER_TIMEOUT`          渲染超时
  `IMAGE_TOO_LARGE`         图片像素或尺寸超过限制
  `PNG_ENCODE_ERROR`        PNG 编码失败
  `OUTPUT_WRITE_ERROR`      输出文件写入失败

错误信息应包含可定位上下文，例如文件名、行号、列号、节点 ID 或边
ID；不得只返回堆栈文本。

### 10.4 日志和指标

每个任务至少记录：

-   taskId、输入格式、图形类型。
-   输入字节数、节点数、边数。
-   Parser、Layout、Render、PNG Encode 各阶段耗时。
-   最终逻辑尺寸、像素尺寸、PNG 文件大小。
-   Flutter Engine 初始化方式和渲染后端。
-   成功 / 失败状态和错误码。

后续 HTTP 服务增加队列长度、Worker 存活、任务失败率、P50 / P95
渲染耗时和内存峰值指标。

------------------------------------------------------------------------

## 11. 测试策略

### 11.1 Parser 单元测试

每种格式准备独立 Fixture：

-   正常输入。
-   空图 / 单节点图。
-   多节点、多关系。
-   循环关系。
-   缺失字段。
-   非法语法。
-   重复 ID。
-   不存在的引用。
-   中文、特殊字符、引号和长文本。
-   大文件和深层嵌套。

SQL Fixture
应覆盖复合主键、复合外键、Schema、保留字标识符和不同数据类型。Mermaid
Fixture 应覆盖方向、节点形状、边标签和语法错误位置。

### 11.2 Graph Domain 测试

-   节点和边引用完整性。
-   ID 唯一性。
-   Schema Version 迁移。
-   布局配置合法性。
-   领域模型到 FFlow Node / Edge 的映射正确性。
-   FFlow JSON 导入导出 Round-trip。

### 11.3 Layout 测试

-   LR / RL / TB / BT 四个方向。
-   无环图、循环图、孤立节点和多连通图。
-   ER 图中的环和多对多关系。
-   Parent Group / 子节点布局。
-   不同节点尺寸。
-   极端长标签和字段数量较多的表。
-   重复执行布局时的稳定性。

### 11.4 渲染与 PNG 测试

使用 Golden Test 和图片元数据检查：

-   PNG 文件头和解码有效性。
-   输出像素宽高符合预期。
-   背景色和透明背景符合配置。
-   节点、边、标签没有被裁切。
-   中文字体正常。
-   高倍率输出清晰。
-   超限图片被拒绝或按策略处理。
-   同一输入在固定环境下输出稳定。
-   连续渲染多张图片后内存没有持续增长。

Golden Test 需固定 Flutter
SDK、操作系统镜像和字体文件。跨平台渲染可能存在抗锯齿差异，应按平台维护基准图或使用容差比较，不应要求不同
GPU / OS 的像素逐点完全相同。

### 11.5 端到端测试

至少包含以下场景：

1.  输入 FFlow JSON → 隐藏渲染 → PNG。
2.  输入通用 Graph JSON → 自动布局 → PNG。
3.  输入 SQL DDL → ER 图 → PNG。
4.  输入 Mermaid Flowchart → 流程图 → PNG。
5.  同一进程连续执行多个任务。
6.  在目标桌面系统中隐藏渲染视图，不显示窗口且不抢占用户焦点。
7.  错误输入、超时、超大图和磁盘写入失败。

------------------------------------------------------------------------

## 12. 研发阶段与里程碑

工期为初步估算，实际以桌面隐藏渲染 PoC
的结论为准。建议先完成渲染风险验证，再扩展输入格式。

### Phase 0：桌面隐藏渲染技术验证（约 3--5 个工作日）

**目标：证明 FFlow 能在目标桌面 GUI 环境中隐藏运行，并可靠导出完整
PNG。**

任务：

-   建立独立最小 Flutter Desktop 渲染 Host，不依赖完整示例编辑器页面。
-   创建固定的 FFlow Canvas，包含自定义 Node、Edge 和中文文本。
-   使用 `RepaintBoundary.toImage()` 捕获 PNG。
-   优先在产品目标桌面系统上验证隐藏渲染视图方案。
-   验证隐藏视图仍会持续完成 Layout 和 Paint。
-   验证隐藏窗口不会抢占用户焦点、闪现或干扰宿主窗口。
-   测试大于当前窗口尺寸的完整图形导出。
-   验证连续任务执行和资源释放。
-   记录 Flutter Engine、窗口后端、字体和目标 OS 版本。

交付物：

-   可运行的桌面 PoC。
-   PNG 样例和自动化测试。
-   技术决策记录（ADR）：确定采用宿主内隐藏渲染视图、独立隐藏窗口，或需要进一步评估离屏
    Engine。

**退出条件：**
在目标桌面系统中，隐藏渲染过程不干扰用户，且能够重复生成内容完整、尺寸正确的
PNG。未通过前，不进入大规模 Parser 开发。

### Phase 1：渲染引擎基础（约 1--2 周）

任务：

-   建立 `DiagramDocument`、Node、Edge、Layout、Theme 模型。
-   建立 FFlow Adapter。
-   实现桌面 Hidden Rendering Host。
-   实现完整 Graph Bounds 计算。
-   实现 PNG Capture / Encode / File Writer。
-   加入字体加载、超时、资源释放和尺寸限制。
-   实现 FFlow JSON 导入和导出。
-   提供桌面宿主可调用的 Dart API。
-   可选实现复用同一 API 的本地 CLI 调试工具。

交付物：

-   桌面渲染服务 API。
-   FFlow JSON → PNG 的端到端能力。
-   标准 Graph JSON → PNG 的端到端能力。
-   桌面端集成示例。
-   单元测试和 Golden Test。

### Phase 2：ER 图能力（约 1--2 周）

任务：

-   选择并固定首个 SQL 方言。
-   实现 SQL DDL Parser Adapter。
-   实现 Table / Column / Constraint / Relationship 领域模型。
-   实现 ER Node Builder。
-   实现主键、外键、唯一键视觉表达。
-   实现 Crow's Foot Edge Renderer。
-   评估 Force Layout 和 ER 专用布局效果。
-   准备真实 DDL Fixture。

交付物：

-   SQL DDL → ER DiagramDocument。
-   ER 图自动布局。
-   ER 图 PNG 导出。
-   支持范围和语法限制文档。

### Phase 3：流程图能力（约 1--2 周）

任务：

-   实现 Mermaid Flowchart Parser。
-   实现节点形状和条件分支映射。
-   实现边标签。
-   映射 LR / RL / TB / BT 布局方向。
-   验证循环流程和复杂边路由。
-   准备 Mermaid Fixture。

交付物：

-   Mermaid Flowchart → DiagramDocument。
-   流程图自动布局。
-   流程图 PNG 导出。
-   Mermaid 子集支持说明。

### Phase 4：桌面集成与稳定性（约 1--2 周）

任务：

-   完善桌面宿主 API、错误码和日志。
-   将隐藏渲染模块集成到目标桌面应用。
-   实现桌面应用内部的批量任务入口（如确有需要）。
-   增加任务超时、资源限制和清理机制。
-   验证连续渲染稳定性、焦点行为和窗口生命周期。
-   进行性能测试和内存测试。
-   完善桌面端打包、签名（如适用）和发布流程。

交付物：

-   可集成的桌面渲染模块。
-   桌面端集成示例或 Demo。
-   性能测试报告。
-   故障排查文档。
-   发布版本和变更记录。

### Phase 5：扩展（单独排期）

-   DBML。
-   BPMN 2.0 XML。
-   SVG / PDF。
-   大图分块渲染。
-   更多布局引擎和 SQL 方言。

## 13. 里程碑验收标准

  --------------------------------------------------------------------------------------------
  ID                      验收项                  通过标准
  ----------------------- ----------------------- --------------------------------------------
  AC-01                   隐藏 GUI                运行期间用户看不到渲染窗口或编辑器界面

  AC-02                   桌面集成                在目标桌面应用 /
                                                  桌面会话中可初始化并调用渲染 Host

  AC-03                   不干扰用户              渲染不抢焦点、不闪窗、不阻断宿主 UI 交互

  AC-04                   FFlow JSON              可导入合法 FFlow Snapshot 并恢复节点、边

  AC-05                   通用 JSON               可按定义的 JSON Schema 构建图

  AC-06                   SQL DDL                 支持范围内的 DDL 可生成正确 ER 结构

  AC-07                   Mermaid                 支持子集可生成正确流程节点和连线

  AC-08                   自动布局                布局结果无节点重叠，主要标签可读

  AC-09                   完整 PNG                图形边界、节点、边和标签均不被裁切

  AC-10                   清晰度                  支持 1x / 2x / 3x 输出倍率

  AC-11                   中文字体                中文文本不缺字、不乱码

  AC-12                   稳定性                  连续处理至少 100 个小 /
                                                  中型任务，无崩溃和持续内存增长

  AC-13                   错误处理                非法输入、超限和渲染失败返回明确错误码

  AC-14                   桌面发布                提供目标桌面平台的可集成构建产物和运行说明
  --------------------------------------------------------------------------------------------

性能目标应在 Phase 0 / Phase 1
建立基准后确定，不应在没有测量前承诺固定毫秒数。建议至少记录
20、100、500 个节点规模的耗时和内存曲线。

## 14. 主要风险与应对措施

  -----------------------------------------------------------------------------------------------------------------
  风险                     影响                    应对
  ------------------------ ----------------------- ----------------------------------------------------------------
  隐藏视图未执行 Paint     PNG 无内容或偶发空白    Phase 0 验证 Render Pipeline；确保渲染子树真实参与布局和绘制

  隐藏窗口被 OS 降低帧率   截图时机不稳定          不以最小化作为唯一隐藏方式；通过帧完成信号和目标 OS 测试确认

  隐藏窗口抢占焦点或闪现   干扰最终用户            测试窗口创建、显示状态、焦点和生命周期；优先采用宿主内隐藏视图

  `RepaintBoundary`        大图被裁切              依据 Graph Bounds 建立完整渲染区域
  只捕获视口                                       

  中文字体缺失             文本显示异常            固定桌面运行环境字体并做中文 Golden Test

  FFlow 默认布局不适合 ER  节点重叠、边交叉多      先做真实数据评估，再引入 ER 专用布局或 ELK

  Mermaid 语法复杂         Parser 维护成本高       明确首期语法子集，采用语法解析而非纯正则

  SQL 方言差异             解析结果不一致          方言 Adapter 和 Fixture 分开管理

  单 Engine 多任务状态污染 输出错误、内存增长      首期串行任务；必要时采用独立渲染视图或桌面进程隔离

  大图导致内存溢出         桌面宿主卡顿或崩溃      像素上限、任务超时、内存监控和后续分块渲染

  不同桌面环境图片差异     Golden Test 不稳定      固定 SDK / 字体 / OS，按平台维护基准图
  -----------------------------------------------------------------------------------------------------------------

## 15. 建议的代码目录

建议在现有 FFlow SDK
之外增加独立的应用层模块，避免把业务解析器和桌面宿主逻辑耦合进图形核心库。

``` text
FFlow/
├── lib/
│   ├── fflow.dart
│   └── src/                         # 现有 FFlow SDK
├── packages/
│   ├── diagram_domain/
│   ├── diagram_parsers/
│   │   ├── lib/src/fflow_json/
│   │   ├── lib/src/graph_json/
│   │   ├── lib/src/sql_ddl/
│   │   └── lib/src/mermaid/
│   ├── fflow_diagram_adapter/
│   │   ├── lib/src/node_builders/
│   │   ├── lib/src/edge_renderers/
│   │   └── lib/src/layout_profiles/
│   └── fflow_render_host/
│       ├── lib/src/render_host.dart
│       ├── lib/src/hidden_render_view.dart
│       ├── lib/src/png_capture.dart
│       ├── lib/src/canvas_bounds.dart
│       └── test/
├── apps/
│   └── desktop_host/                # 桌面宿主集成示例（按需）
├── tool/
│   ├── diagram_render.dart          # 可选 CLI / 调试入口
│   └── render_smoke_test.dart
└── docs/
    ├── hidden-rendering-architecture.md
    ├── input-format-support.md
    └── desktop-integration.md
```

如果仓库暂时不采用 Dart Workspace，可先以单 package
多目录方式实现，待依赖边界稳定后再拆分。桌面宿主可以直接依赖
`fflow_render_host`，解析器和领域模型不应依赖具体窗口管理代码。

## 16. 开发优先级

### P0：必须先做

1.  桌面 Hidden Rendering Host 技术验证。
2.  目标桌面平台隐藏渲染与 PNG Capture PoC。
3.  完整画布 Bounds 和 PNG 导出。
4.  DiagramDocument 统一模型。
5.  FFlow JSON 导入和导出。
6.  桌面宿主 Dart API 最小闭环。

### P1：首个可用版本

1.  SQL DDL → ER 图。
2.  Mermaid Flowchart → 流程图。
3.  ER / Flowchart 自定义 Node 和 Edge Renderer。
4.  自动布局配置。
5.  中文字体和多倍率 PNG。
6.  桌面应用集成与端到端测试。

### P2：增强能力

1.  DBML / BPMN。
2.  SVG / PDF。
3.  大图分块渲染。
4.  多 SQL 方言和更多布局引擎。
5.  如确有需要，再增加本地 IPC 或批处理接口。

## 17. 首轮开发任务清单

建议按以下顺序开工，不要同时铺开所有 Parser：

-   [ ] 确认目标桌面宿主和首个目标操作系统。
-   [ ] 创建独立的 Flutter Desktop Hidden Render Host Demo。
-   [ ] 验证 `RepaintBoundary.toImage()` 可捕获 FFlow Canvas。
-   [ ] 验证隐藏视图状态下仍会执行完整 Layout / Paint。
-   [ ] 验证渲染不会闪窗、抢占焦点或影响宿主窗口。
-   [ ] 验证中文字体和中文节点内容。
-   [ ] 验证超出当前窗口视口范围的节点能被完整导出。
-   [ ] 验证连续 20 次渲染没有空白图或资源泄漏。
-   [ ] 固化渲染方案 ADR。
-   [ ] 定义 `DiagramDocument` JSON Schema。
-   [ ] 完成 FFlow Snapshot → PNG 的 Dart API 最小闭环。
-   [ ] 将渲染 API 集成到桌面宿主 Demo。

**Phase 0 未通过前，不建议投入 SQL / Mermaid Parser 的完整开发。**
如果底层桌面隐藏渲染路径不稳定，后续所有输入格式开发都会受到影响。

## 18. 参考资料与仓库入口

-   FFlow 仓库：<https://github.com/risol/FFlow>
-   FFlow README：<https://github.com/risol/FFlow/blob/master/README.md>
-   FFlow Graph
    Snapshot：<https://github.com/risol/FFlow/blob/master/lib/src/models/flow_graph_snapshot.dart>
-   FFlow Layered
    Layout：<https://github.com/risol/FFlow/blob/master/lib/src/interactions/flow_layered_layout.dart>
-   FFlow
    Canvas：<https://github.com/risol/FFlow/blob/master/lib/src/canvas/flow_canvas.dart>
-   FFlow Example：<https://github.com/risol/FFlow/tree/master/example>
-   Flutter
    `RepaintBoundary`：<https://api.flutter.dev/flutter/rendering/RenderRepaintBoundary/toImage.html>
-   Flutter
    `ImageByteFormat`：<https://api.flutter.dev/flutter/dart-ui/ImageByteFormat.html>
-   Flutter Desktop
    integration：<https://docs.flutter.dev/platform-integration/desktop>

------------------------------------------------------------------------

## 19. 最终交付定义

本项目完成后，应交付一套可集成到桌面应用中的图形生成与渲染模块，而不只是
FFlow 编辑器上的一个"导出图片"按钮。

最终能力应包括：

1.  多种结构化输入格式。
2.  统一图形领域模型。
3.  ER 图和流程图的自动构建。
4.  FFlow 自动布局和真实 Flutter GUI 渲染复用。
5.  在桌面 GUI 环境中隐藏运行，不向最终用户展示渲染窗口。
6.  渲染不抢占焦点、不闪窗、不干扰宿主应用。
7.  完整画布 PNG 导出。
8.  JSON 图形数据导入、导出。
9.  可供桌面宿主调用的 Dart API。
10. 完整测试、错误处理和桌面集成文档。

**最终原则：使用桌面系统已有的 GUI / Windowing 环境，保留 Flutter /
FFlow
的真实渲染能力，将渲染视图隐藏在后台，由输入数据驱动图形生成，最终只向宿主应用返回
PNG 或 JSON 等结果，不要求部署服务器、Docker 或虚拟显示环境。**
