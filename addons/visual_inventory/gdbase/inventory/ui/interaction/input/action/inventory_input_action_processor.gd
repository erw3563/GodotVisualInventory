@abstract
class_name InventoryInputActionProcessor
extends Resource
## 库存输入动作处理协议。静态 Processor 可共享；Host 局部适配器由 Assembly 独占。
##
## 动作契约：process 返回三态结果——PASS 放行同一路由上后续 Processor，
## HANDLED / REJECTED 均消费输入并终止链（「拒绝不得回退普通拿放」即靠
## REJECTED 与 HANDLED 同为终局实现）。context 为只读快照不得保存；
## 处理器不自行监听输入，只接受统一入口分发。


@abstract func process(
	context: InventoryInputActionContext
) -> InventoryInputActionResult
