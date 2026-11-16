# SPDX-License-Identifier: 0BSD
extends Node

var previous_ticks := 60


func _enter_tree() -> void:
	previous_ticks = Engine.physics_ticks_per_second
	Engine.physics_ticks_per_second = 120
	Engine.max_fps = 60


func _exit_tree() -> void:
	Engine.physics_ticks_per_second = previous_ticks
