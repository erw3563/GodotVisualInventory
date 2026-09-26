@tool
@abstract
class_name ItemAnimationContent
extends Resource
## 内容只保存配置；独立执行对象保存时间。新内容通过协议扩展。
enum Channel { APPEARANCE, FEEDBACK }

@abstract func get_channel() -> Channel
@abstract func get_duration() -> float
@abstract func validate_configuration() -> StringName
@abstract func sample(elapsed: float) -> Dictionary

func create_execution(looping := false) -> ItemAnimationExecution:
	var execution := ItemAnimationExecution.new()
	execution.duration = get_duration()
	execution.looping = looping
	execution.sampler = sample
	return execution
