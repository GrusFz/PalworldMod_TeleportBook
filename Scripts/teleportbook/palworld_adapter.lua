local adapter = {}
local post_teleport_check_delays_ms = { 750, 2000 }

local function log(message)
	print("[TeleportBook] " .. message .. "\n")
end

function adapter.set_post_teleport_check_delays(delays_ms)
	if type(delays_ms) ~= "table" then
		return
	end

	local configured_delays = {}
	for _, delay_ms in ipairs(delays_ms) do
		if type(delay_ms) == "number" and delay_ms > 0 then
			table.insert(configured_delays, math.floor(delay_ms))
		end
	end
	if #configured_delays > 0 then
		post_teleport_check_delays_ms = configured_delays
	end
end

local function is_valid(object)
	if not object then
		return false
	end
	local ok, valid = pcall(function()
		return object:IsValid()
	end)
	return ok and valid
end

local function unwrap(value)
	if value and type(value) == "userdata" and type(value.get) == "function" then
		local ok, unwrapped = pcall(function()
			return value:get()
		end)
		if ok then
			return unwrapped
		end
	end
	return value
end

local read_vector

local function make_vector_from_actor(actor, x, y, z)
	local last_error = "could not retrieve an actor location struct"
	for _, getter in ipairs({
		function() return actor:K2_GetActorLocation() end,
		function() return actor:GetActorLocation() end,
		function() return actor.ActorLocation end,
	}) do
		local ok, vector_or_error = pcall(getter)
		if ok then
			local vector = unwrap(vector_or_error)
			if vector then
				local set_ok, set_error = pcall(function()
					vector.X = x
					vector.Y = y
					vector.Z = z
				end)
				if set_ok then
					local check_x, check_y, check_z = read_vector(vector)
					if check_x
						and math.abs(check_x - x) <= 0.5
						and math.abs(check_y - y) <= 0.5
						and math.abs(check_z - z) <= 0.5 then
						return vector
					end
					last_error = "location struct values could not be updated"
				else
					last_error = tostring(set_error)
				end
			end
		else
			last_error = tostring(vector_or_error)
		end
	end

	return nil, last_error
end

read_vector = function(vector)
	local ok, x, y, z = pcall(function()
		return vector.X, vector.Y, vector.Z
	end)
	if ok and type(x) == "number" and type(y) == "number" and type(z) == "number" then
		return x, y, z
	end
	return nil
end

local function object_name(object)
	local ok, name = pcall(function()
		return object:GetFullName()
	end)
	if ok and name then
		return tostring(name)
	end
	return "<unknown>"
end

local function diagnostic_value(label, getter)
	local ok, value = pcall(getter)
	if ok then
		return label .. "=" .. tostring(unwrap(value))
	end
	return label .. "=<unavailable>"
end

local function log_network_context(actor, controller)
	local details = {
		"actor=" .. object_name(actor),
		"controller=" .. object_name(controller),
		diagnostic_value("actor.HasAuthority", function() return actor:HasAuthority() end),
		diagnostic_value("actor.LocalRole", function() return actor:GetLocalRole() end),
		diagnostic_value("actor.RemoteRole", function() return actor:GetRemoteRole() end),
		diagnostic_value("controller.HasAuthority", function() return controller:HasAuthority() end),
		diagnostic_value("controller.IsLocal", function() return controller:IsLocalController() end),
	}
	log("Teleport network context: " .. table.concat(details, ", "))
end

local function read_member(object, member_name)
	local ok, value = pcall(function()
		return object[member_name]
	end)
	if ok then
		return unwrap(value)
	end
	return nil
end

local function read_player_uid_key(player_uid)
	player_uid = unwrap(player_uid)
	if not player_uid then
		return nil
	end

	local parts = {}
	for _, key in ipairs({ "A", "B", "C", "D" }) do
		local ok, value = pcall(function()
			return player_uid[key]
		end)
		if ok and value ~= nil then
			table.insert(parts, tostring(unwrap(value)))
		end
	end
	if #parts > 0 then
		return table.concat(parts, ":")
	end

	local ok, text = pcall(function()
		return tostring(player_uid)
	end)
	if ok then
		return text
	end
	return nil
end

local function is_player_in_stage(controller)
	local player_state = read_member(controller, "PlayerState")
	if not is_valid(player_state) then
		return nil, "player state is unavailable"
	end
	local ok, in_stage = pcall(function()
		return player_state:IsInStage()
	end)
	if not ok then
		return nil, tostring(in_stage)
	end
	return in_stage == true
end

function adapter.get_controller()
	for _, controller in ipairs(FindAllOf("PalPlayerController") or {}) do
		if is_valid(controller) then
			return controller
		end
	end
	local controller = FindFirstOf("PalPlayerController")
	if is_valid(controller) then
		return controller
	end
	return nil
end

function adapter.find_controller_by_player_uid(player_uid)
	local expected_key = read_player_uid_key(player_uid)
	if not expected_key then
		return nil, "sender player UID is unavailable"
	end

	for _, controller in ipairs(FindAllOf("PalPlayerController") or {}) do
		if is_valid(controller) then
			local ok, controller_uid = pcall(function()
				return controller:GetPlayerUId()
			end)
			if ok and read_player_uid_key(controller_uid) == expected_key then
				return controller
			end
		end
	end

	return nil, "no player controller matched sender UID"
end

local function get_actor_for_controller(controller)
	for _, getter in ipairs({
		function() return controller:GetControlledPawn() end,
		function() return controller:K2_GetPawn() end,
		function() return controller.Pawn end,
		function() return controller.AcknowledgedPawn end,
	}) do
		local ok, actor = pcall(getter)
		actor = unwrap(actor)
		if ok and is_valid(actor) then
			return actor
		end
	end
	return nil
end

function adapter.get_player_actor()
	local controller = adapter.get_controller()
	if not controller then
		return nil, nil, "player controller is unavailable"
	end

	local actor = get_actor_for_controller(controller)
	if actor then
		return actor, controller
	end
	return nil, controller, "player pawn is unavailable"
end

local function get_actor_location(actor)
	for _, getter in ipairs({
		function() return actor:K2_GetActorLocation() end,
		function() return actor:GetActorLocation() end,
		function() return actor.ActorLocation end,
	}) do
		local ok, vector = pcall(getter)
		if ok then
			local x, y, z = read_vector(unwrap(vector))
			if x then
				return { x = x, y = y, z = z }
			end
		end
	end
	return nil, "could not read actor location"
end

function adapter.get_location()
	local actor, _, err = adapter.get_player_actor()
	if not actor then
		return nil, err
	end
	local location, location_err = get_actor_location(actor)
	if not location then
		return nil, location_err
	end
	return location
end

function adapter.set_ui_input_enabled(enabled)
	local controller = adapter.get_controller()
	if not controller then
		return nil, "player controller is unavailable"
	end
	pcall(function() controller.bShowMouseCursor = enabled end)
	pcall(function() controller.bEnableClickEvents = enabled end)
	pcall(function() controller.bEnableMouseOverEvents = enabled end)
	pcall(function() controller:SetShowMouseCursor(enabled) end)
	return true
end

function adapter.get_mouse_position()
	local controller = adapter.get_controller()
	if not controller then
		return nil
	end
	local ok, a, b, c = pcall(function()
		return controller:GetMousePosition()
	end)
	if ok and type(a) == "boolean" and a and type(b) == "number" and type(c) == "number" then
		return b, c
	end
	if ok and type(a) == "number" and type(b) == "number" then
		return a, b
	end
	return nil
end

local function distance_to(point, location)
	return math.sqrt(
		(location.x - point.x) ^ 2 + (location.y - point.y) ^ 2 + (location.z - point.z) ^ 2
	)
end

local function schedule_post_teleport_check(actor, point, tolerance, delays_ms)
	local execute_in_game_thread_with_delay = rawget(_G, "ExecuteInGameThreadWithDelay")
	if type(execute_in_game_thread_with_delay) ~= "function" then
		log("Delayed replication check unavailable in this UE4SS build.")
		return
	end

	for _, delay_ms in ipairs(delays_ms or post_teleport_check_delays_ms) do
		local ok, err = pcall(function()
			execute_in_game_thread_with_delay(delay_ms, function()
				if not is_valid(actor) then
					log("Post-teleport check skipped: target actor is no longer valid.")
					return
				end
				local location, location_err = get_actor_location(actor)
				if not location then
					log("Post-teleport check failed: " .. tostring(location_err))
					return
				end

				local distance = distance_to(point, location)
				log(string.format(
					"Post-teleport location after %d ms: %.3f, %.3f, %.3f (distance %.1f)",
					delay_ms,
					location.x,
					location.y,
					location.z,
					distance
				))
				if distance <= tolerance then
					log("Teleport arrival confirmed by replicated position.")
				elseif delay_ms >= 2000 then
					log("Teleport arrival was not confirmed after the respawn timeout.")
				end
			end)
		end)
		if not ok then
			log("Could not schedule delayed replication check: " .. tostring(err))
		end
	end
end

local function teleport_actor_to_point(actor, controller, point, tolerance)
	local destination, vector_err = make_vector_from_actor(actor, point.x, point.y, point.z)
	if not destination then
		return nil, "could not create destination vector: " .. tostring(vector_err)
	end
	log(string.format("Teleport request: %.3f, %.3f, %.3f", point.x, point.y, point.z))
	log_network_context(actor, controller)

	local has_authority_ok, has_authority = pcall(function()
		return actor:HasAuthority()
	end)
	local in_stage, stage_err = is_player_in_stage(controller)
	if in_stage == nil then
		return nil, "could not determine dungeon state: " .. tostring(stage_err)
	end

	if not has_authority_ok or not has_authority then
		if in_stage then
			log("Dungeon stage detected; using direct local teleport.")
		else
			return nil,
				"server-authoritative teleport is required on dedicated servers; "
					.. "this client has no server-visible trigger configured"
		end
	end

	local invoked = false
	for _, attempt in ipairs({
		{
			name = "K2_TeleportTo",
			call = function()
				return actor:K2_TeleportTo(destination, actor:K2_GetActorRotation())
			end,
		},
		{
			name = "TeleportTo",
			call = function()
				return actor:TeleportTo(destination, actor:K2_GetActorRotation(), false, true)
			end,
		},
	}) do
		local ok, result = pcall(attempt.call)
		log(string.format("Teleport API %s: ok=%s, result=%s", attempt.name, tostring(ok), tostring(result)))
		if ok and result ~= false then
			invoked = true
			break
		end
	end
	if not invoked then
		return nil, "no supported teleport API accepted the request"
	end

	local location, location_err = get_actor_location(actor)
	if not location then
		return nil, "teleport was called but verification failed: " .. location_err
	end
	local distance = distance_to(point, location)
	log(string.format(
		"Immediate post-teleport location: %.3f, %.3f, %.3f (distance %.1f)",
		location.x,
		location.y,
		location.z,
		distance
	))
	if distance > tolerance then
		return nil, string.format("teleport was rejected or corrected (distance %.1f)", distance)
	end
	schedule_post_teleport_check(actor, point, tolerance, { 750 })
	return true, nil, "direct"
end

function adapter.teleport(point, tolerance)
	local actor, controller, err = adapter.get_player_actor()
	if not actor then
		return nil, err
	end
	return teleport_actor_to_point(actor, controller, point, tolerance)
end

function adapter.teleport_controller(controller, point, tolerance)
	controller = unwrap(controller)
	if not is_valid(controller) then
		return nil, "target player controller is unavailable"
	end
	local actor = get_actor_for_controller(controller)
	if not actor then
		return nil, "target player pawn is unavailable"
	end
	return teleport_actor_to_point(actor, controller, point, tolerance)
end

function adapter.parse_chat_message(chat_message)
	local candidates = { chat_message }

	chat_message = unwrap(chat_message)
	if chat_message ~= nil then
		table.insert(candidates, chat_message)
	end

	if type(chat_message) == "table" then
		for _, key in ipairs({ "ChatMessage", "Message", "Payload", "Arg1", "Param1" }) do
			local nested = chat_message[key]
			if nested ~= nil then
				table.insert(candidates, unwrap(nested))
			end
		end
	end

	for _, payload in ipairs(candidates) do
		if payload ~= nil then
			local message = read_member(payload, "Message")
				or read_member(payload, "Text")
				or read_member(payload, "Msg")
			local sender = read_member(payload, "Sender")
				or read_member(payload, "SenderName")
			local sender_player_uid = read_member(payload, "SenderPlayerUId")
				or read_member(payload, "PlayerUId")
				or read_member(payload, "SenderUid")
			if message ~= nil then
				return {
					message = tostring(message),
					sender = sender and tostring(sender) or "<unknown>",
					sender_player_uid = sender_player_uid,
				}
			end
		end
	end

	return nil, "chat message text is unavailable"
end

function adapter.has_authority(object)
	object = unwrap(object)
	if not is_valid(object) then
		return false
	end
	local ok, has_authority = pcall(function()
		return object:HasAuthority()
	end)
	return ok and has_authority == true
end

return adapter