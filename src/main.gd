## Entry point: straight into a race with --race=<id>, otherwise the menus.
extends Node


func _ready() -> void:
	for a in DevArgs.all():
		if a.begins_with("--time-scale="):
			# time_scale multiplies the physics delta; raise the tick rate by the same
			# factor so every simulation step stays 1/60 s of game time.
			var k := float(a.substr(13))
			Engine.time_scale = k
			Engine.physics_ticks_per_second = int(round(60.0 * k))
			Engine.max_physics_steps_per_frame = int(16 * k)
	await get_tree().process_frame
	var direct := false
	for a in DevArgs.all():
		if a.begins_with("--race=") or a.begins_with("--career=") or a.begins_with("--cup="):
			direct = true
	var screen := "home"
	for a in DevArgs.all():
		if a.begins_with("--menu="):
			screen = a.substr(7)
	if direct or not ResourceLoader.exists(Game.MENU_SCRIPT):
		Game.start_race(Game.default_cfg())
	else:
		Game.goto_menu(screen)
