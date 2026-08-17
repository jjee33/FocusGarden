extends SceneTree
## Reports what the machine is actually rendering with.
##
##     ... --path . --script res://tools/probe_renderer.gd
##
## Written while chasing an idle CPU figure that stayed pinned at 100% no matter
## what the frame cap or redraw rate was set to. The usual cause of that pattern
## is a software OpenGL/Vulkan fallback, where every frame is drawn on the CPU —
## and no amount of application-side tuning will fix it, because the cost is not
## in the application.

func _init() -> void:
	await process_frame
	await process_frame

	print("\n=== Renderer ===")
	print("  adapter        : %s" % RenderingServer.get_video_adapter_name())
	print("  vendor         : %s" % RenderingServer.get_video_adapter_vendor())
	print("  api version    : %s" % RenderingServer.get_video_adapter_api_version())
	print("  adapter type   : %s" % _adapter_type_name(RenderingServer.get_video_adapter_type()))
	print("  rendering      : %s" % ProjectSettings.get_setting("rendering/renderer/rendering_method", "?"))
	print("  max_fps        : %d" % Engine.max_fps)
	print("  vsync mode     : %d" % DisplayServer.window_get_vsync_mode())

	# Measure the frame rate actually achieved over a second of doing nothing.
	var frames := 0
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 1000:
		await process_frame
		frames += 1
	print("  idle fps       : %d" % frames)

	if RenderingServer.get_video_adapter_type() == RenderingDevice.DEVICE_TYPE_CPU:
		print("\n  SOFTWARE RENDERING: every frame is drawn on the CPU.")
		print("  Idle CPU cannot be fixed application-side on this machine.")
	print("")
	quit(0)


func _adapter_type_name(type: int) -> String:
	match type:
		RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU:
			return "integrated GPU"
		RenderingDevice.DEVICE_TYPE_DISCRETE_GPU:
			return "discrete GPU"
		RenderingDevice.DEVICE_TYPE_VIRTUAL_GPU:
			return "virtual GPU"
		RenderingDevice.DEVICE_TYPE_CPU:
			return "CPU (software)"
		_:
			return "other/unknown"
