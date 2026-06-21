extends CharacterBody2D

# Adjust this number to make the chef faster or slower
const SPEED = 150.0

func _physics_process(delta):
	# Get the input direction from the keyboard
	var direction = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	
	# Apply the speed to the direction
	if direction:
		velocity = direction * SPEED
	else:
		velocity = Vector2.ZERO

	# This built-in function moves the character and stops them when they hit a collision box
	move_and_slide()
