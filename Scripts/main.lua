local source = debug.getinfo(1, "S").source:gsub("^@", ""):gsub("\\", "/")
local scripts_path = source:match("^(.*)/[^/]+$")
package.path = scripts_path .. "/?.lua;" .. scripts_path .. "/?/init.lua;" .. package.path

local config = require("teleportbook.config")
local store_module = require("teleportbook.teleport_store")
local game = require("teleportbook.palworld_adapter")

game.set_post_teleport_check_delays(config.respawn_teleport_check_delays_ms)

local mod_root = source:match("^(.*)/Scripts/[^/]+$")
local data_path = mod_root .. "/" .. config.data_file_name
local store = store_module.new(data_path)
local listen_mode = false

local loaded, load_err = store:load()
if loaded then
	print(string.format("[TeleportBook] Loaded %d point(s).\n", #store:get_points()))
else
	print("[TeleportBook] Failed to load teleports.json: " .. tostring(load_err) .. "\n")
end

local function save_current_location()
	local location, location_err = game.get_location()
	if not location then
		print("[TeleportBook] Could not read player location: " .. tostring(location_err) .. "\n")
		return
	end

	local point, save_err = store:add_current_location(location.x, location.y, location.z)
	if not point then
		print("[TeleportBook] Failed to save current location: " .. tostring(save_err) .. "\n")
		return
	end

	print(
		string.format(
			"[TeleportBook] Saved %s: %s\n",
			point.name,
			store.format_coordinates(point)
		)
	)
end

local function reload_points()
	local ok, err = store:load()
	if not ok then
		print("[TeleportBook] Failed to reload teleports.json: " .. tostring(err) .. "\n")
		return nil
	end
	return store:get_points()
end

local function teleport_to_index(index)
	local points = reload_points()
	if not points then
		return
	end

	local point = points[index]
	if not point then
		print(string.format("[TeleportBook] No point at index %d.\n", index))
		return
	end

	local ok, err, method = game.teleport(point, config.teleport_tolerance)
	if not ok then
		print(
			string.format(
				"[TeleportBook] Failed to teleport to #%d (%s): %s\n",
				index,
				point.name,
				tostring(err)
			)
		)
		return
	end

	if method == "respawn" then
		print(
			string.format(
				"[TeleportBook] Requested server respawn teleport to #%d %s: %s\n",
				index,
				point.name,
				store.format_coordinates(point)
			)
		)
	else
		print(
			string.format(
				"[TeleportBook] Teleported to #%d %s: %s\n",
				index,
				point.name,
				store.format_coordinates(point)
			)
		)
	end
end

local function run_game_action(label, action)
	local execute_in_game_thread = rawget(_G, "ExecuteInGameThread")
	if type(execute_in_game_thread) == "function" then
		local ok, err = pcall(function()
			execute_in_game_thread(action)
		end)
		if ok then
			print("[TeleportBook] Queued " .. label .. " on the game thread.\n")
			return
		end
		print(
			"[TeleportBook] Could not queue "
				.. label
				.. " on the game thread; using direct callback: "
				.. tostring(err)
				.. "\n"
		)
	else
		print("[TeleportBook] Game-thread scheduling is unavailable; using direct callback.\n")
	end

	local ok, err = pcall(action)
	if not ok then
		print("[TeleportBook] " .. label .. " failed: " .. tostring(err) .. "\n")
	end
end

local function on_g_pressed()
	run_game_action("save current location", save_current_location)
end

local function on_l_pressed()
	listen_mode = not listen_mode
	print("[TeleportBook] Listen mode = " .. tostring(listen_mode) .. "\n")
	if listen_mode then
		reload_points()
	end
end

local function make_numpad_callback(index)
	return function()
		if not listen_mode then
			return
		end
		run_game_action("teleport to slot " .. tostring(index), function()
			teleport_to_index(index)
		end)
	end
end

local function first_key(...)
	for index = 1, select("#", ...) do
		local key = select(index, ...)
		if key ~= nil then
			return key
		end
	end
	return nil
end

local function bind_async(key_value, callback, label)
	if key_value == nil then
		print("[TeleportBook] Skip keybind (missing key): " .. tostring(label) .. "\n")
		return false
	end

	local ok, err = pcall(function()
		RegisterKeyBindAsync(key_value, {}, callback)
	end)
	if ok then
		print("[TeleportBook] Bound key: " .. tostring(label) .. "\n")
	else
		print(
			"[TeleportBook] Failed to bind "
				.. tostring(label)
				.. ": "
				.. tostring(err)
				.. "\n"
		)
	end
	return ok
end

bind_async(first_key(Key.G), on_g_pressed, "G")
bind_async(first_key(Key.L), on_l_pressed, "L")

local numpad_bindings = {
	{ key = first_key(Key.NUM_ONE), index = 1, label = "NUM1" },
	{ key = first_key(Key.NUM_TWO), index = 2, label = "NUM2" },
	{ key = first_key(Key.NUM_THREE), index = 3, label = "NUM3" },
	{ key = first_key(Key.NUM_FOUR), index = 4, label = "NUM4" },
	{ key = first_key(Key.NUM_FIVE), index = 5, label = "NUM5" },
	{ key = first_key(Key.NUM_SIX), index = 6, label = "NUM6" },
	{ key = first_key(Key.NUM_SEVEN), index = 7, label = "NUM7" },
	{ key = first_key(Key.NUM_EIGHT), index = 8, label = "NUM8" },
	{ key = first_key(Key.NUM_NINE), index = 9, label = "NUM9" },
}

for _, binding in ipairs(numpad_bindings) do
	bind_async(binding.key, make_numpad_callback(binding.index), binding.label)
end

print(
	"[TeleportBook] Ready. Press G to save the current location. "
		.. "Press L to toggle listen mode, then press numpad 1-9 "
		.. "to teleport by teleports.json order.\n"
)