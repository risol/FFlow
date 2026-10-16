# FFlow 拖拽稳定性专项改造 Plan

> 目标：系统性解决 FFlow 中“点击拖动时偶发无法拖动”与“拖动了错误对象”的交互稳定性问题。  
> 范围：Pointer 命中、Gesture Arena、Node/Handle/Resize/Pan 竞争、重叠对象选择、Pointer Capture、交互状态机、回归测试。  
> 优先级：P0  
> 建议在继续扩展更多 React Flow 功能前完成。

---

## 1. 背景

当前 FFlow 已支持：

- Node 拖动
- 多选节点拖动
- Handle 连线
- Edge reconnect
- Node resize
- Canvas pan / zoom
- Selection box
- Node 内部自定义 Widget
- `dragHandleOnly`
- `zIndex`
- selected elevation
- parent / child subflow

随着交互能力增加，当前实现中存在多套 Pointer 命中与 Gesture 决策逻辑并存的问题。

用户侧典型表现：

1. 鼠标按住节点后，有时完全无法拖动。
2. 点击 A 节点，却拖动了 B 节点。
3. 两个节点重叠时，拖动对象与视觉最上层对象不一致。
4. Node 内部按钮、输入框、Handle、Resize Handle 与 Node Drag 抢手势。
5. 快速连续点击 / 拖动后，可能残留上一次 interaction 状态。
6. 远离画布原点、负坐标或经过 viewport 平移后，Pointer 命中可能出现偏差。
7. Canvas Pan 与 Node Drag 同时竞争，导致偶发拖动失败。

这类问题不能继续通过在各个 `GestureDetector` 上局部加条件解决，建议改造成统一的交互基础设施。

---

# 2. 核心问题定义

本专项需要解决两个主问题。

## P0-A：偶发无法拖动

可能来源包括：

- Node `GestureDetector` 与 `InteractiveViewer` 同时参与 Gesture Arena。
- `FFlowNodeDragHandle` 与外层 Node `GestureDetector` 嵌套竞争。
- `FlowPort`、Resize Handle 与 Node Drag 同时可命中。
- Pointer down 已发生，但 Pan recognizer 未赢得 Gesture Arena。
- Node 位于 viewport-sized scene bounds 外时，Flutter Widget hit-test 无法命中。
- Pointer 状态在 `cancel` / `up` / `pan cancel` 时没有统一清理。
- Canvas pan recognizer 已取得 gesture ownership。
- Pointer 在 drag threshold 附近产生 click / pan / drag 不稳定切换。

## P0-B：拖动错误对象

当前存在两套“目标对象判定”：

```text
Pointer Down
    │
    ├─ 外层 Listener
    │    └─ 手工 geometry hit-test
    │         └─ hitNode = A
    │
    └─ Flutter Widget hit-test / Gesture Arena
         └─ GestureDetector
              └─ _startNodeDrag(node = B)
```

即：

```text
Selection Target != Drag Target
```

这是结构性风险。

目标架构必须保证：

> 一次 Pointer Down 确定 interaction target 后，在 Pointer Up / Cancel 前，该 Pointer 对应的目标对象不可改变。

---

# 3. 当前架构中的主要风险点

## 3.1 多套 Hit-Test 规则

当前至少存在：

```text
_handlePointerDown()
_nodeAt()
_edgeAt()
Node GestureDetector
FFlowNodeDragHandle
FlowPort GestureDetector
Resize Handle GestureDetector
InteractiveViewer
MouseRegion
```

其中 Node 命中范围并不完全相同。

例如可能出现：

```text
click       -> nodeRect.contains()
hover       -> nodeRect.inflate(12)
contextmenu -> _nodeAt()
drag        -> Flutter RenderBox hit-test
```

因此同一坐标可能得到不同 target。

---

## 3.2 Drag Target 使用全局字段保存

当前类似：

```dart
String? _draggingNodeId;
```

这种全局字段无法完整表达一次 interaction。

它缺少：

- pointerId
- pointer down 时的 target
- interaction 类型
- start position
- initial node state
- active modifier keys
- ownership
- cancel reason
- threshold 状态

随着 resize / connect / reconnect / selection 等功能增加，状态字段会越来越多，并产生非法组合。

例如理论上可能同时出现：

```text
_draggingNodeId != null
_reconnectingEdgeId != null
_selectionDragActive == true
```

即使代码当前尽量避免，也没有统一状态模型保证其不发生。

---

## 3.3 Gesture Arena 决定权分散

目前 Node、Handle、Resize、Canvas 都可能自己注册 recognizer。

对于复杂 Node：

```text
Node
 ├─ TextField
 ├─ Button
 ├─ Slider
 ├─ ScrollView
 ├─ Handle
 └─ DragHandle
```

继续叠加 `GestureDetector` 会让 Gesture Arena 行为难以预测。

专项目标应从：

> “各 Widget 自己决定交互”

改成：

> “Canvas Interaction Manager 统一决定 graph interaction；内部 Widget 只声明交互意图或阻止某类 graph gesture。”

---

# 4. 目标架构

建议新增三个核心模块：

```text
FlowHitTestEngine
FlowPointerCapture
FlowInteractionController
```

整体结构：

```text
Pointer Event
    │
    ▼
FlowHitTestEngine
    │
    ▼
FlowHitResult
    │
    ▼
FlowPointerCapture
    │
    ▼
FlowInteractionController
    │
    ├─ pressed
    ├─ draggingNode
    ├─ resizingNode
    ├─ connecting
    ├─ reconnecting
    ├─ selecting
    └─ panning
    │
    ▼
Graph Mutation / Callback
```

---

# 5. FlowHitTestEngine

## 5.1 目标

所有 graph interaction 使用同一个 authoritative hit-test。

建议接口：

```dart
FlowHitResult hitTest(
  Offset flowPosition, {
  required FlowHitTestPurpose purpose,
});
```

## 5.2 FlowHitResult

建议：

```dart
sealed class FlowHitResult {
  const FlowHitResult();
}

class FlowResizeHandleHit extends FlowHitResult {
  final String nodeId;
  final FlowResizeDirection direction;
}

class FlowReconnectHandleHit extends FlowHitResult {
  final String edgeId;
  final bool sourceSide;
}

class FlowHandleHit extends FlowHitResult {
  final String nodeId;
  final String handleId;
  final FlowHandleType handleType;
}

class FlowNodeHit extends FlowHitResult {
  final String nodeId;
}

class FlowEdgeHit extends FlowHitResult {
  final String edgeId;
}

class FlowPaneHit extends FlowHitResult {}
```

## 5.3 命中优先级

建议固定：

```text
1. Node Resize Handle
2. Edge Reconnect Handle
3. Node Connection Handle
4. Node Interactive Region
5. Node Drag Handle
6. Node Body
7. Edge
8. Pane
```

必须保证 hit-test 顺序和真实 paint order 一致。

## 5.4 重叠 Node 规则

必须统一考虑：

- parent depth
- `zIndex`
- `elevateNodesOnSelect`
- source list order

最终应该只有一个方法计算 node order：

```dart
List<FlowNode<T>> getNodePaintOrder();
```

以下逻辑全部复用：

```text
paint
hit-test
hover
contextmenu
selection target
drag target
```

禁止各自重新排序。

---

# 6. Pointer Capture

## 6.1 原则

Pointer Down 时：

```text
hitTest()
   ↓
capture pointerId + target
```

之后直到 Pointer Up / Cancel：

```text
PointerMove
DragStart
DragUpdate
DragEnd
Selection
Resize
Connect
Reconnect
```

都不能重新决定 target。

## 6.2 数据结构

建议：

```dart
class FlowPointerCapture {
  final int pointerId;
  final FlowHitResult target;

  final Offset downViewportPosition;
  final Offset downFlowPosition;

  final Set<LogicalKeyboardKey> modifiers;

  final DateTime startedAt;
}
```

如果未来支持多 pointer：

```dart
Map<int, FlowPointerCapture> _pointerCaptures;
```

桌面环境也建议从第一版就按 pointerId 设计，避免未来触控扩展再次重构。

## 6.3 Capture 生命周期

```text
PointerDown
    ↓
capture
    ↓
Pressed State
    ↓
超过 threshold
    ↓
具体 Interaction
    ↓
PointerUp / PointerCancel
    ↓
release capture
```

任何：

```text
PointerCancel
GestureCancel
Widget dispose
Graph target deleted
Canvas loses interaction
```

都必须释放 capture。

---

# 7. Interaction State Machine

建议替换多个分散字段。

当前不要继续扩展：

```text
_draggingNodeId
_resizingNodeId
_reconnectingEdgeId
_connectingNodeId
_selectionDragActive
...
```

统一为：

```dart
FlowInteractionSession? _interaction;
```

## 7.1 状态定义

建议：

```text
Idle
Pressed
NodeDragging
NodeResizing
Connecting
Reconnecting
SelectionDragging
CanvasPanning
```

状态转移：

```text
Idle
 └─ PointerDown
      ↓
    Pressed
      ├─ threshold -> NodeDragging
      ├─ threshold -> NodeResizing
      ├─ threshold -> Connecting
      ├─ threshold -> Reconnecting
      ├─ threshold -> SelectionDragging
      ├─ threshold -> CanvasPanning
      └─ PointerUp -> Click
```

## 7.2 非法状态必须不可能出现

例如：

```text
NodeDragging + CanvasPanning
NodeDragging + Connecting
Resizing + SelectionDragging
Connecting + Reconnecting
```

必须从数据结构层面禁止，而不是靠布尔条件互相判断。

---

# 8. Drag Threshold

点击与拖动应严格区分。

建议新增：

```dart
final double nodeDragThreshold;
final double connectionDragThreshold;
final double selectionDragThreshold;
final double panePanThreshold;
```

默认例如：

```text
node: 3~5 logical pixels
connection: 3
selection: 3
pan: Flutter touch slop 或自定义
```

规则：

```text
distance < threshold
=> click candidate

distance >= threshold
=> interaction committed
```

一旦进入 drag：

```text
不能再触发 click
不能切换 target
```

---

# 9. Gesture Ownership

## 9.1 Node Drag 与 Canvas Pan

规则应明确：

```text
Pointer Down on draggable node
=> Node owns gesture

Pointer Down on pane
=> Canvas may own pan

Pointer Down on node interactive child
=> Child owns gesture

Pointer Down on handle
=> Connect owns gesture

Pointer Down on resize handle
=> Resize owns gesture
```

不要依赖最终谁“碰巧”赢得 Gesture Arena。

## 9.2 NoDrag / NoPan / NoWheel

建议新增：

```dart
FFlowNoDrag
FFlowNoPan
FFlowNoWheel
```

Node 内部：

```dart
FFlowNoDrag(
  child: TextField(...),
)
```

也可以支持组合：

```dart
FFlowInteractionBlocker(
  drag: true,
  pan: true,
  wheel: false,
  child: ...
)
```

用于：

- TextField
- Slider
- ScrollView
- Dropdown
- Button
- Editor
- Embedded custom component

---

# 10. dragHandleOnly 重构

当前 `FFlowNodeDragHandle` 本身注册 `GestureDetector`，容易和 Node 外层 GestureDetector 竞争。

建议改成“语义标记”，而不是独立 drag recognizer。

例如：

```dart
FFlowNodeDragHandle(
  child: ...
)
```

内部只负责在 hit-test metadata 中标记区域：

```text
this region may start node drag
```

真正 Drag Session 仍由 Canvas Interaction Manager 创建。

目标：

```text
dragHandleOnly = true
```

时：

- Node body 不允许启动拖动
- DragHandle 区域允许
- Button/Handle/Resize 等高优先级区域仍优先

---

# 11. Scene / Viewport Hit-Test 修复

必须和本专项一起解决。

当前无限画布不能只依赖：

```text
viewport-sized Stack
+
clipBehavior: Clip.none
```

因为：

```text
Paint Bounds != Hit-Test Bounds
```

专项验收必须包含：

```text
node x = 3000
pan viewport 到该 node
点击 node
拖动 node
点击 node 内 Button
拖动 Handle
拖 Resize Handle
```

全部正常。

同时测试：

```text
negative x / y
large positive coordinate
zoom 0.25
zoom 2.0
```

---

# 12. 坐标系统统一

统一四类坐标：

```text
Global
Viewport Local
Flow / Scene
Node Local
```

禁止交互逻辑直接混用。

建议：

```dart
class FlowCoordinateConverter {
  Offset globalToViewport(...);
  Offset viewportToFlow(...);
  Offset flowToViewport(...);
  Offset globalToFlow(...);
}
```

所有 Pointer 事件统一从：

```text
global -> viewport -> flow
```

一次转换。

Drag delta 建议：

```text
global delta
-> viewport delta
-> flow delta / zoom
```

需要验证 transform 中如果未来出现非 uniform scale / rotation 时的行为。

---

# 13. Node Drag Session

建议：

```dart
class FlowNodeDragSession extends FlowInteractionSession {
  final int pointerId;
  final String primaryNodeId;

  final Set<String> movingNodeIds;

  final Offset downFlowPosition;
  final Offset lastFlowPosition;

  final Map<String, Offset> initialPositions;
}
```

## 13.1 Multi Selection Drag

Pointer Down 在已选节点 A：

```text
selected = A,B,C
target = A
```

drag session：

```text
primaryNode = A
movingNodes = A,B,C
```

Pointer Down 在未选节点 D：

```text
select D
primaryNode = D
movingNodes = D
```

不得出现：

```text
Pointer target = D
drag primary = A
```

---

# 14. Parent / Child Node 规则

必须明确 parent / child overlap 时谁拿 gesture。

建议：

```text
视觉最上层可交互 node 优先
```

但需要考虑 group node。

可增加：

```dart
FlowNode.hitTestBehavior
```

例如：

```text
opaque
translucent
childrenOnly
```

Group node 可用：

```text
childrenOnly
```

避免 parent 覆盖整个 child interaction。

---

# 15. Resize / Handle / Drag 冲突

必须保证：

```text
resize handle > connection handle > drag node
```

测试：

```text
鼠标在 resize handle 上按下
=> 不允许启动 node drag

鼠标在 connection handle 上按下
=> 不允许启动 node drag

鼠标在 node body 上按下
=> 不允许误启动 resize/connect
```

---

# 16. Pointer Cancel 清理

必须实现统一：

```dart
void cancelInteraction(FlowInteractionCancelReason reason)
```

原因：

```text
pointerCancel
targetRemoved
canvasDisposed
focusLost
gestureCancelled
graphReplaced
externalControllerReset
```

取消必须清理：

```text
pointer capture
interaction session
dragging state
connection preview
resize state
selection rectangle
auto-pan ticker
temporary hover state
```

---

# 17. Auto Pan 与 Drag

当前 Auto Pan 应与 active interaction session 绑定。

建议：

```text
NodeDragging
Connecting
Reconnecting
SelectionDragging
```

可启用 auto-pan。

而且不能只依赖 `PointerMove`。

需要：

```text
Ticker / AnimationController
```

持续检测 Pointer 是否位于 viewport edge。

即：

```text
pointer 停在边缘
=> canvas 仍持续 pan
=> interaction target 仍保持 capture
```

---

# 18. Hover 与 Drag Target 分离

Hover 可以随鼠标变化。

Capture target 不能变化。

例如：

```text
dragging A
pointer 移动到 B 上方
```

允许：

```text
hover target = B
```

但：

```text
drag target = A
```

必须保持。

因此需要区分：

```text
hoverHit
capturedHit
```

---

# 19. 重叠节点专项测试矩阵

## 19.1 两个普通节点

```text
A below B
```

测试：

- A 独占区域 -> A
- B 独占区域 -> B
- overlap -> B
- 调整 zIndex 后 -> 新 top node
- selected elevation 后 -> 与真实 paint order 相同

## 19.2 Parent / Child

测试：

```text
parent background
child node
```

- child 区域 -> child
- parent 空白区域 -> parent
- child drag -> parent 不动
- parent drag -> child absolute position 跟随

## 19.3 多选重叠

```text
A + B selected
C unselected
```

测试：

- PointerDown C -> C 成为 primary target
- PointerDown A -> selected set 整体拖动
- drag 过程中穿过 C -> target 不改变

---

# 20. Node 内部交互控件测试

必须新增 demo/test node：

```text
TextField
Button
Slider
Checkbox
Dropdown
Scrollable List
MouseRegion
GestureDetector child
```

期望：

| 控件 | 点击 | 拖动 | Node Drag |
|---|---|---|---|
| Button | Button | Button gesture | 否 |
| TextField | Focus | text select | 否 |
| Slider | slider | slider | 否 |
| ScrollView | focus | scroll | 否 |
| Node body | select | drag node | 是 |
| DragHandle | select | drag node | 是 |

---

# 21. 建议新增源码文件

建议拆出：

```text
lib/src/interactions/
  flow_hit_test.dart
  flow_pointer_capture.dart
  flow_interaction_session.dart
  flow_interaction_controller.dart
  flow_interaction_policy.dart
```

原：

```text
flow_canvas_pointer.dart
flow_canvas_nodes.dart
flow_canvas_connections.dart
```

逐步降级为 UI adapter。

---

# 22. 建议修改文件

## 必改

```text
lib/src/canvas/flow_canvas.dart
lib/src/canvas/flow_canvas_pointer.dart
lib/src/canvas/flow_canvas_nodes.dart
lib/src/canvas/flow_canvas_connections.dart
lib/src/canvas/flow_canvas_selection.dart
lib/src/canvas/flow_canvas_viewport.dart
```

## 新增

```text
lib/src/interactions/flow_hit_test.dart
lib/src/interactions/flow_pointer_capture.dart
lib/src/interactions/flow_interaction_session.dart
lib/src/interactions/flow_interaction_controller.dart
```

## 可能修改

```text
lib/src/models/flow_node.dart
lib/src/models/flow_events.dart
lib/src/rendering/flow_port.dart
lib/fflow.dart
```

---

# 23. 实施阶段

## Phase 0 — Reproduction Baseline

目标：

先把当前 Bug 固化成自动测试。

新增：

```text
test/interaction/
  node_drag_target_test.dart
  overlapping_nodes_test.dart
  drag_handle_test.dart
  node_child_controls_test.dart
  offscreen_hit_test_test.dart
```

必须先写失败测试，再改代码。

验收：

```text
可以稳定复现至少一类：
- drag fails
- wrong target drag
```

## Phase 1 — Unified Hit-Test

实现：

```text
FlowHitTestEngine
FlowHitResult
```

把以下逻辑统一：

```text
PointerDown
hover
context menu
node selection
drag candidate
```

暂时保留现有 GestureDetector。

目标：

先消除：

```text
selection target != hit-test target
```

## Phase 2 — Pointer Capture

PointerDown 后建立：

```text
pointerId -> target
```

所有 drag 生命周期使用 capture target。

删除：

```text
drag start 时再次从 Widget closure 决定 target
```

目标：

彻底消除：

```text
down A
drag B
```

## Phase 3 — Interaction State Machine

将分散字段迁移到：

```dart
FlowInteractionSession? _interaction;
```

迁移：

```text
node drag
resize
connect
reconnect
selection
```

最后迁移 canvas pan ownership。

## Phase 4 — Gesture Isolation

实现：

```text
FFlowNoDrag
FFlowNoPan
FFlowNoWheel
```

重构：

```text
FFlowNodeDragHandle
FlowPort
resize handles
```

减少嵌套 drag GestureDetector。

## Phase 5 — Infinite Canvas Hit-Test

修复 scene RenderBox / hit-test bounds。

覆盖：

```text
large positive
negative coordinate
pan/zoom
offscreen node brought into viewport
```

## Phase 6 — Auto Pan / Cancellation

实现：

```text
ticker-based auto pan
uniform cancelInteraction()
```

覆盖异常生命周期。

---

# 24. 测试要求

## 24.1 Widget Tests

至少覆盖：

```text
single node drag
rapid node switching
overlapping nodes
zIndex
selected elevation
parent child
multi-selection drag
dragHandleOnly
TextField inside node
Button inside node
Slider inside node
connection handle
resize handle
edge reconnect
canvas pan
selection drag
pointer cancel
zoomed canvas
negative coordinate node
far offscreen node
```

## 24.2 Stress Tests

模拟：

```text
连续 500 次：
pointerDown A
small move
drag
pointerUp
pointerDown B
drag
pointerUp
```

检查：

```text
target mismatch == 0
stale session == 0
stale pointer capture == 0
```

## 24.3 Randomized Interaction Tests

构造：

```text
20 nodes
部分 overlap
随机 zIndex
部分 parent child
部分 selected
```

随机执行：

```text
down
move
up
cancel
zoom
pan
select
```

每轮检查 invariant：

```text
max 1 active interaction
capture pointer == session pointer
drag node exists
target cannot mutate
after up -> no capture
after cancel -> no capture
```

---

# 25. Debug Instrumentation

建议开发模式增加：

```dart
debugInteractionOverlay: true
```

显示：

```text
hover target
captured target
active interaction
pointerId
flow coordinate
viewport coordinate
drag delta
```

例如：

```text
Hover: Node B
Capture: Node A
Interaction: NodeDragging
Pointer: 14
Flow: (1840, -320)
Zoom: 0.75
```

这对排查“偶现”交互 Bug 很有价值。

---

# 26. Logging

建议：

```dart
FlowInteractionDiagnostics
```

开发模式日志：

```text
pointer.down id=4 hit=node:A
capture.acquire id=4 target=node:A
interaction.transition pressed -> nodeDragging
drag.update target=node:A
pointer.up id=4
capture.release id=4
interaction.transition nodeDragging -> idle
```

当用户反馈：

> “偶尔拖错”

可以直接看 interaction trace。

---

# 27. API 新增建议

建议新增 Canvas 参数：

```dart
nodeDragThreshold
connectionDragThreshold
selectionDragThreshold
interactionPolicy
debugInteractionOverlay
```

可考虑：

```dart
onInteractionStart
onInteractionEnd
onInteractionCancel
```

不建议暴露过多底层 recognizer。

---

# 28. Performance 注意事项

统一 hit-test 后不能每次 PointerMove 全量扫描所有 node/edge。

第一版：

```text
nodes:
reverse paint order scan
```

后续大图：

```text
spatial index
```

例如：

```text
R-tree
quadtree
grid buckets
```

但本专项第一目标是 correctness。

原则：

```text
Correctness > Performance
```

先统一行为，再缓存。

---

# 29. Definition of Done

本专项完成必须满足全部条件。

## Target correctness

- PointerDown 的 node 和最终 drag node 永远一致。
- overlap 时拖动对象和视觉最上层对象一致。
- Pointer capture 生命周期内 target 不改变。
- multi-selection primary node 正确。

## Drag reliability

- 连续快速拖动不同节点，无随机失败。
- Node Drag 不再被 Canvas Pan 随机抢占。
- dragHandleOnly 行为稳定。
- node 内控件不会误触 node drag。

## Interaction exclusivity

任意时刻：

```text
最多一个 graph interaction state
```

不存在：

```text
drag + resize
drag + connect
drag + pan
selection + connect
```

## Coordinate correctness

以下场景行为一致：

```text
zoom 0.25
zoom 1
zoom 2
negative coordinates
far positive coordinates
parent relative node
origin != Offset.zero
```

## Lifecycle

以下操作后 interaction 必须完全清理：

```text
PointerUp
PointerCancel
Widget Dispose
Target Delete
Graph Reset
```

## Tests

新增专项测试全部通过。

CI 必须阻止拖拽回归。

---

# 30. GitHub Issue 拆分建议

## P0-01 Unified Hit-Test Engine

实现统一 graph hit-test。

Acceptance:

- Node click / hover / context / drag target 使用同一 order。
- overlap 与 paint order 一致。

## P0-02 Pointer Capture

PointerDown 后锁定目标对象。

Acceptance:

```text
pointer down A
move over B
drag target remains A
```

## P0-03 Interaction State Machine

合并分散交互状态字段。

Acceptance:

```text
only one active graph interaction
```

## P0-04 Fix Node Drag vs Canvas Pan Arbitration

Node 拖动必须稳定获得 interaction ownership。

Acceptance:

```text
1000 次 node drag 无随机 canvas pan
```

## P0-05 Fix Infinite Canvas Hit-Test

修复 viewport bounds 外 node widget hit-test。

Acceptance:

```text
x=3000 node pan into view
button / drag / handle / resize all work
```

## P0-06 Gesture Isolation Widgets

新增：

```text
FFlowNoDrag
FFlowNoPan
FFlowNoWheel
```

## P0-07 Drag Threshold

实现 click / drag 明确状态切换。

## P0-08 Overlapping Nodes Regression Suite

覆盖：

```text
zIndex
selection elevation
parent/child
multi-select
```

## P0-09 Interactive Child Regression Suite

覆盖：

```text
TextField
Button
Slider
ScrollView
```

## P1-01 Ticker Auto Pan

Pointer 不移动时仍持续 auto-pan。

## P1-02 Interaction Diagnostics Overlay

开发模式显示 interaction state。

## P1-03 Randomized Interaction Fuzz Tests

加入随机 Pointer State Machine 测试。

---

# 31. 推荐提交顺序

建议 PR 不要一次性大重构。

```text
PR 1
test: add drag target regression tests

PR 2
refactor: centralize graph hit testing

PR 3
feat: add pointer capture

PR 4
refactor: introduce interaction state machine

PR 5
fix: stabilize node drag and canvas pan ownership

PR 6
feat: add no-drag/no-pan interaction regions

PR 7
fix: infinite canvas widget hit testing

PR 8
feat: ticker based auto pan

PR 9
test: interaction fuzz and stress suite
```

这样每个 PR 都能单独验证，不会把 interaction 全部一次推倒导致难以定位回归。

---

# 32. 最终目标

专项完成后，FFlow 的 Pointer 模型应满足：

```text
Pointer Down
    ↓
Single Authoritative Hit-Test
    ↓
Pointer Capture
    ↓
Single Interaction State
    ↓
Stable Target
    ↓
Mutation
    ↓
Pointer Up / Cancel
    ↓
Full Cleanup
```

核心原则：

> Pointer 按下时决定“操作谁”，拖动过程中只决定“怎么操作”，不再决定“操作谁”。

这条规则应成为后续：

```text
drag
resize
connect
reconnect
grouping
helper lines
drag-to-create
clipboard drag
collaboration cursor
```

所有交互功能的基础。

---

# 33. 优先级结论

该专项建议放在 FFlow Roadmap 最前面。

顺序：

```text
1. Drag Target Correctness
2. Pointer Capture
3. Gesture Ownership
4. Infinite Canvas Hit-Test
5. Interaction State Machine
6. Regression Tests
7. Performance Optimization
8. 新 React Flow 功能
```

原因：

如果 Pointer / Gesture 基础层不稳定，后续增加任何编辑能力都会扩大问题面。

因此应把本专项视为：

```text
FFlow Interaction Foundation v1
```

而不是普通 Bug Fix。
