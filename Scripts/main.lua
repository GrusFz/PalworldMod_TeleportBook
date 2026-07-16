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

local function get_hook_context_object(context)
	local ok, object = pcall(function()
		return context:get()
	end)
	if ok then
		return object
	end
	return nil
end

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

local function teleport_sender_to_index(sender_player_uid, sender_name, index)
	local points = reload_points()
	if not points then
		return nil, "teleport list could not be loaded"
	end

	local point = points[index]
	if not point then
		print(string.format("[TeleportBook] No point at index %d for chat sender %s.\n", index, sender_name))
		return nil, "no teleport point configured at that slot"
	end

	local controller, controller_err = game.find_controller_by_player_uid(sender_player_uid)
	if not controller then
		print(
			"[TeleportBook] Could not resolve chat sender controller: "
				.. tostring(controller_err)
				.. "\n"
		)
		return nil, "could not resolve sender controller"
	end

	local ok, err = game.teleport_controller(controller, point, config.teleport_tolerance)
	if not ok then
		print(
			string.format(
				"[TeleportBook] Failed chat teleport for %s to #%d (%s): %s\n",
				sender_name,
				index,
				point.name,
				tostring(err)
			)
		)
		return nil, tostring(err)
	end

	print(
		string.format(
			"[TeleportBook] Server chat teleported %s to #%d %s: %s\n",
			sender_name,
			index,
			point.name,
			store.format_coordinates(point)
		)
	)

	return true
end

local function send_system_message(controller, message)
	if controller == nil or message == nil then
		return
	end
	local chunk = tostring(message)
	if chunk == "" then
		return
	end

	local ok, err = pcall(function()
		local utility = StaticFindObject("/Script/Pal.Default__PalUtility")
		if utility ~= nil then
			utility:SendSystemAnnounce(controller, chunk)
		end
	end)
	if not ok then
		print("[TeleportBook] Could not send system message: " .. tostring(err) .. "\n")
	end
end

local function resolve_sender_controller_from_payload(parsed)
	if not parsed or parsed.sender_player_uid == nil then
		return nil
	end
	local controller = game.find_controller_by_player_uid(parsed.sender_player_uid)
	return controller
end

local function is_controller_like(object)
	if object == nil then
		return false
	end
	local ok, uid = pcall(function()
		return object:GetPlayerUId()
	end)
	return ok and uid ~= nil
end

local function resolve_controller_from_context_object(context_object)
	if is_controller_like(context_object) then
		return context_object
	end
	for _, key in ipairs({ "PlayerController", "Owner", "Outer" }) do
		local ok, candidate = pcall(function()
			return context_object and context_object[key]
		end)
		if ok and is_controller_like(candidate) then
			return candidate
		end
	end
	return nil
end

local function read_command_text(value)
	if value == nil then
		return nil
	end
	if type(value) == "string" then
		return value
	end
	for _, key in ipairs({ "Command", "Text", "Message", "Str", "Input" }) do
		local ok, nested = pcall(function()
			return value[key]
		end)
		if ok and type(nested) == "string" and nested ~= "" then
			return nested
		end
	end
	local ok, as_text = pcall(function()
		return tostring(value)
	end)
	if ok and as_text and as_text ~= "" then
		return as_text
	end
	return nil
end

local function parse_tp_slot_from_text(text)
	if type(text) ~= "string" then
		return nil
	end
	local normalized = text:lower()
	local slot_text = normalized:match("^%s*!tp%s+(%d+)%s*$")
	if not slot_text then
		return nil
	end
	local index = tonumber(slot_text)
	if not index or index < 1 or index > 9 then
		return nil
	end
	return index
end

local function teleport_controller_to_index(controller, sender_name, index)
	local points = reload_points()
	if not points then
		return nil, "teleport list could not be loaded"
	end

	local point = points[index]
	if not point then
		return nil, "no teleport point configured at that slot"
	end

	local ok, err = game.teleport_controller(controller, point, config.teleport_tolerance)
	if not ok then
		return nil, tostring(err)
	end

	print(
		string.format(
			"[TeleportBook] Server command teleported %s to #%d %s: %s\n",
			sender_name,
			index,
			point.name,
			store.format_coordinates(point)
		)
	)

	return true
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

local function handle_chat_command(context, ...)
	local parsed
	for i = 1, select("#", ...) do
		local candidate = select(i, ...)
		parsed = game.parse_chat_message(candidate)
		if parsed then
			break
		end
	end

	if not parsed then
		local context_object = get_hook_context_object(context)
		parsed = game.parse_chat_message(context_object)
	end

	if not parsed then
		return
	end

	local normalized = tostring(parsed.message):lower()
	local index = parse_tp_slot_from_text(normalized)
	if not index then
		return
	end

	local sender_controller = resolve_sender_controller_from_payload(parsed)
	if not sender_controller then
		print("[TeleportBook] !tp command ignored: sender controller not found.\n")
		return
	end

	run_game_action("server chat teleport for " .. parsed.sender, function()
		local ok, err = teleport_sender_to_index(parsed.sender_player_uid, parsed.sender, index)
		if ok then
			send_system_message(sender_controller, "[TeleportBook] Teleported to slot " .. tostring(index) .. ".")
		else
			send_system_message(sender_controller, "[TeleportBook] Teleport failed: " .. tostring(err))
		end
	end)
end

local function handle_tp_command_from_controller(controller, command_text, source_label)
	local index = parse_tp_slot_from_text(command_text)
	if not index then
		return
	end

	local sender_name = "player"
	local ok, name = pcall(function()
		return controller:GetFullName()
	end)
	if ok and name then
		sender_name = tostring(name)
	end

	run_game_action("server !tp command from " .. source_label, function()
		local success, err = teleport_controller_to_index(controller, sender_name, index)
		if success then
			send_system_message(controller, "[TeleportBook] Teleported to slot " .. tostring(index) .. ".")
		else
			send_system_message(controller, "[TeleportBook] Teleport failed: " .. tostring(err))
		end
	end)
end

local function handle_cheat_command(context, ...)
	local context_object = get_hook_context_object(context)
	local controller = resolve_controller_from_context_object(context_object)
	if not controller then
		return
	end

	for i = 1, select("#", ...) do
		local command_text = read_command_text(select(i, ...))
		if command_text then
			handle_tp_command_from_controller(controller, command_text, "Debug_CheatCommand_ToServer")
			return
		end
	end
end

local function handle_console_pre_hook(context, ...)
	local context_object = get_hook_context_object(context)
	local controller = resolve_controller_from_context_object(context_object)
	if not controller then
		return
	end

	for i = 1, select("#", ...) do
		local command_text = read_command_text(select(i, ...))
		if command_text then
			handle_tp_command_from_controller(controller, command_text, "ConsoleExec")
			return
		end
	end
end

local register_hook = rawget(_G, "RegisterHook")

if type(register_hook) == "function" then
	local chat_hook_targets = {
		"/Script/Pal.PalPlayerState:EnterChat_Receive",
		"/Script/Pal.PalGameStateInGame:BroadcastChatMessage",
		"/Script/Pal.PalPlayerController:Debug_CheatCommand_ToServer",
	}

	for _, hook_target in ipairs(chat_hook_targets) do
		local ok, err = pcall(function()
			local handler = handle_chat_command
			if hook_target:find("Debug_CheatCommand_ToServer", 1, true) then
				handler = handle_cheat_command
			end
			register_hook(hook_target, handler)
		end)
		if ok then
			print("[TeleportBook] Registered chat command hook: " .. hook_target .. "\n")
		else
			print(
				"[TeleportBook] Failed to register chat command hook "
					.. hook_target
					.. ": "
					.. tostring(err)
					.. "\n"
			)
		end
	end
end

local register_process_console_exec_pre_hook = rawget(_G, "RegisterProcessConsoleExecPreHook")
if type(register_process_console_exec_pre_hook) == "function" then
	local ok, err = pcall(function()
		register_process_console_exec_pre_hook(handle_console_pre_hook)
	end)
	if ok then
		print("[TeleportBook] Registered ProcessConsoleExec pre-hook for !tp commands.\n")
	else
		print("[TeleportBook] Failed to register ProcessConsoleExec pre-hook: " .. tostring(err) .. "\n")
	end
end

local register_call_function_by_name_with_arguments_pre_hook = rawget(
	_G,
	"RegisterCallFunctionByNameWithArgumentsPreHook"
)
if type(register_call_function_by_name_with_arguments_pre_hook) == "function" then
	local ok, err = pcall(function()
		register_call_function_by_name_with_arguments_pre_hook(handle_console_pre_hook)
	end)
	if ok then
		print("[TeleportBook] Registered CallFunctionByNameWithArguments pre-hook for !tp commands.\n")
	else
		print(
			"[TeleportBook] Failed to register CallFunctionByNameWithArguments pre-hook: "
				.. tostring(err)
				.. "\n"
		)
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