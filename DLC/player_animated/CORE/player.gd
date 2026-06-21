extends CharacterBody2D

# Adjust this number to make the chef faster or slower
const SPEED = 150.0

@onready var animated_sprite: AnimatedSprite2D = $CollisionShape2D/AnimatedSprite2D

var facing := Vector2.DOWN


func _ready() -> void:
	_play_idle()


func _physics_process(_delta):
	# Get the input direction from the keyboard
	var direction = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	
	# Apply the speed to the direction
	if direction:
		velocity = direction * SPEED
		facing = direction
		_play_walk(direction)
	else:
		velocity = Vector2.ZERO
		_play_idle()

	# This built-in function moves the character and stops them when they hit a collision box
	move_and_slide()


func _play_walk(direction: Vector2) -> void:
	if absf(direction.x) > absf(direction.y):
		_play_animation("walk_side", direction.x < 0.0)
	elif direction.y < 0.0:
		_play_animation("walk_up", false)
	else:
		_play_animation("walk_down", false)


func _play_idle() -> void:
	if absf(facing.x) > absf(facing.y):
		_play_animation("idle_side", facing.x < 0.0)
	elif facing.y < 0.0:
		_play_animation("idle_up", false)
	else:
		_play_animation("idle_down", false)


func _play_animation(animation_name: StringName, flip_h: bool) -> void:
	if animated_sprite == null:
		return

	animated_sprite.flip_h = flip_h
	if animated_sprite.animation != animation_name:
		animated_sprite.play(animation_name)
