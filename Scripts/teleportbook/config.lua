local config = {
	data_file_name = "teleports.json",
	ui_backend = "text",
	text_ui_interval_ms = 140,
	retry_delay_ms = 2000,
	max_hook_attempts = 20,
	refresh_interval_ms = 250,
	teleport_tolerance = 100.0,
	respawn_teleport_check_delays_ms = { 750, 2000 },
	colors = {
		background = { 0.06, 0.09, 0.13, 0.82 },
		border = { 0.22, 0.72, 0.96, 1.00 },
		accent = { 0.94, 0.70, 0.18, 1.00 },
		title = { 0.97, 0.99, 1.00, 1.00 },
		text = { 0.82, 0.89, 0.98, 1.00 },
		muted = { 0.62, 0.72, 0.84, 1.00 },
		shadow = { 0.00, 0.00, 0.00, 0.70 },
	},
}

return config