extends GPUParticles3D

func _ready():
	finished.connect(queue_free)
