class_name InventoryReactionAnimationPresenter
extends Node
## 每个共享执行器唯一的业务呈现适配器；事务完成后才调用动画。
var animation_resolver: Callable
var controller: InventoryReactionController
var _handles: Dictionary = {}

func bind(executor: InventoryReactionController, resolver: Callable) -> void:
	unbind()
	controller = executor
	animation_resolver = resolver
	controller.reaction_finished.connect(_on_reaction_finished)
	controller.session_reset.connect(cancel_playbacks)

func _on_reaction_finished(item: ItemInstanceData, rule: ItemReactionRule, result: InventoryOperationResult) -> void:
	var processor := animation_resolver.call() as ItemAnimationProcessor if animation_resolver.is_valid() else null
	if result == null or not result.success or rule == null or rule.success_animation_key.is_empty() or not is_instance_valid(processor):
		return
	var handle := processor.play(item, rule.success_animation_key)
	if not handle.is_finished():
		var id := handle.get_instance_id()
		_handles[id] = handle
		handle.finished.connect(_on_finished.bind(id), CONNECT_ONE_SHOT)

func _on_finished(id: int) -> void:
	_handles.erase(id)

func cancel_playbacks() -> void:
	for handle in _handles.values():
		handle.cancel()
	_handles.clear()

func unbind() -> void:
	cancel_playbacks()
	if is_instance_valid(controller):
		if controller.reaction_finished.is_connected(_on_reaction_finished):
			controller.reaction_finished.disconnect(_on_reaction_finished)
		if controller.session_reset.is_connected(cancel_playbacks):
			controller.session_reset.disconnect(cancel_playbacks)
	controller = null
	animation_resolver = Callable()

func _exit_tree() -> void:
	unbind()
