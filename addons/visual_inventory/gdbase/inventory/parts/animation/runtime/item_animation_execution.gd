class_name ItemAnimationExecution
extends RefCounted
## 每个视图独占计时；有限动画与持续循环共用纯采样配置。
var looping := false
var elapsed := 0.0
var duration := 0.0
var sampler: Callable

func advance(delta: float) -> Dictionary:
	if not is_finite(duration) or duration <= 0.0 or not is_finite(delta):
		return {}
	elapsed = fposmod(elapsed + maxf(delta, 0.0), duration) if looping else minf(elapsed + maxf(delta, 0.0), duration)
	return sampler.call(elapsed) if sampler.is_valid() else {}

func is_finished() -> bool:
	return not looping and elapsed >= duration
