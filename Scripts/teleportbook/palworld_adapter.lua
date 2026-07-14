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

local function call_method(label, callback)
	local ok, result = pcall(callback)
	log(string.format("%s: ok=%s, result=%s", label, tostring(ok), tostring(result)))
	if not ok then
		return nil, tostring(result)
	end
	if result == false then
		return nil, "returned false"
	end
	return true
end

local function safe_invoke_method(targets, method_name, ...)
	local args = { ... }
	local attempts = {}

	for _, target in ipairs(targets or {}) do
		for _, receiver in ipairs({ target, unwrap(target) }) do
			if receiver ~= nil then
				local member_ok, member_or_err = pcall(function()
					return receiver[method_name]
				end)
				if member_ok and type(member_or_err) == "function" then
					local ok, result = pcall(function()
						return member_or_err(receiver, table.unpack(args))
					end)
					if ok and result ~= false then
						return true, result
					end
					table.insert(attempts, string.format("dot(%s)", tostring(result)))

					ok, result = pcall(function()
						return member_or_err(table.unpack(args))
					end)
					if ok and result ~= false then
						return true, result
					end
					table.insert(attempts, string.format("free(%s)", tostring(result)))
				else
					local detail = member_ok and ("type=" .. type(member_or_err)) or tostring(member_or_err)
					table.insert(attempts, string.format("member(%s)", detail))
				end

				local ok, result = pcall(function()
					return receiver:CallFunctionByNameWithArguments(method_name)
				end)
				if ok and result ~= false then
					return true, result
				end
				table.insert(attempts, string.format("CallFunctionByNameWithArguments(%s)", tostring(result)))
			end
		end
	end

	return nil, table.concat(attempts, " | ")
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

local function is_player_riding(controller)
	local ok, riding = pcall(function()
		return controller:isRiding()
	end)
	if ok then
		return riding == true
	end

	return false
end

local function extract_numeric_hp(value, depth)
	depth = depth or 0
	if depth > 3 then
		return nil
	end

	value = unwrap(value)
	if type(value) == "number" then
		return value
	end
	if type(value) ~= "table" then
		return nil
	end

	for _, key in ipairs({ "CurrentValue", "Value", "HP", "Health", "current", "value", "hp", "health" }) do
		local nested = value[key]
		local numeric = extract_numeric_hp(nested, depth + 1)
		if type(numeric) == "number" then
			return numeric
		end
	end

	return nil
end

local function get_player_health(actor)
	local component = read_member(actor, "CharacterParameterComponent")
	if not is_valid(component) then
		return nil, "character parameter component is unavailable"
	end
	local ok, health = pcall(function()
		return component:GetHP()
	end)
	if not ok or health == nil then
		return nil, "could not read player HP: " .. tostring(health)
	end

	local numeric_hp = extract_numeric_hp(health)
	if type(numeric_hp) ~= "number" then
		return nil, "could not parse player HP value of type " .. type(unwrap(health))
	end

	return numeric_hp
end

local function respawn_teleport(actor, controller, destination)
	if is_player_riding(controller) then
		return nil, "get off your mount before using respawn teleport"
	end

	local transmitter = read_member(controller, "Transmitter")
	local transmitter_player = transmitter and read_member(transmitter, "Player")
	if not is_valid(transmitter_player) then
		return nil, "controller transmitter player is unavailable"
	end

	local player_state = read_member(controller, "PlayerState")
	if not is_valid(player_state) then
		return nil, "player state is unavailable"
	end

	local uid_ok, player_uid = pcall(function()
		return controller:GetPlayerUId()
	end)
	if not uid_ok or not player_uid then
		return nil, "could not read player UID: " .. tostring(player_uid)
	end

	local health, health_err = get_player_health(actor)
	if not health then
		return nil, health_err
	end

	local registered, register_err = call_method("RegisterRespawnLocation_ToServer", function()
		local ok, result_or_err = safe_invoke_method(
			{ transmitter_player, transmitter, controller, player_state, actor },
			"RegisterRespawnLocation_ToServer",
			player_uid,
			destination
		)
		if not ok then
			error(result_or_err)
		end
		return result_or_err
	end)
	if not registered then
		if tostring(register_err):find("TrivialObject", 1, true) then
			return nil, "respawn rpc unavailable: " .. register_err
		end
		return nil, "could not register server respawn location: " .. register_err
	end

	local requested, request_err = call_method("RequestRespawn", function()
		local ok, result_or_err = safe_invoke_method({ player_state }, "RequestRespawn")
		if not ok then
			error(result_or_err)
		end
		return result_or_err
	end)
	if not requested then
		return nil, "could not request respawn: " .. request_err
	end

	local revived, revive_err = call_method("ReviveCharacter_ToServer", function()
		local ok, result_or_err = safe_invoke_method({ actor }, "ReviveCharacter_ToServer", health)
		if not ok then
			error(result_or_err)
		end
		return result_or_err
	end)
	if not revived then
		return nil, "could not request revive: " .. revive_err
	end

	log(string.format("Respawn teleport requested at preserved HP %.1f.", health))
	return true
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

function adapter.get_player_actor()
	local controller = adapter.get_controller()
	if not controller then
		return nil, nil, "player controller is unavailable"
	end

	for _, getter in ipairs({
		function() return controller:GetControlledPawn() end,
		function() return controller:K2_GetPawn() end,
		function() return controller.Pawn end,
		function() return controller.AcknowledgedPawn end,
	}) do
		local ok, actor = pcall(getter)
		actor = unwrap(actor)
		if ok and is_valid(actor) then
			return actor, controller
		end
	end
	return nil, controller, "player pawn is unavailable"
end

function adapter.get_location()
	local actor, _, err = adapter.get_player_actor()
	if not actor then
		return nil, err
	end
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
	return nil, "could not read player location"
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

local function schedule_post_teleport_check(point, tolerance, delays_ms)
	local execute_in_game_thread_with_delay = rawget(_G, "ExecuteInGameThreadWithDelay")
	if type(execute_in_game_thread_with_delay) ~= "function" then
		log("Delayed replication check unavailable in this UE4SS build.")
		return
	end

	for _, delay_ms in ipairs(delays_ms or post_teleport_check_delays_ms) do
		local ok, err = pcall(function()
			execute_in_game_thread_with_delay(delay_ms, function()
				local location, location_err = adapter.get_location()
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

function adapter.teleport(point, tolerance)
	local actor, controller, err = adapter.get_player_actor()
	if not actor then
		return nil, err
	end
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
			log("Dedicated-server client detected; requesting server respawn teleport.")
			local ok, respawn_err = respawn_teleport(actor, controller, destination)
			if not ok then
				if tostring(respawn_err):find("respawn rpc unavailable", 1, true) then
					log("Respawn RPC is unavailable in this runtime; falling back to direct teleport attempt.")
				else
					return nil, respawn_err
				end
			else
				schedule_post_teleport_check(point, tolerance)
				return true, nil, "respawn"
			end
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

	local location, location_err = adapter.get_location()
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
	schedule_post_teleport_check(point, tolerance, { 750 })
	return true, nil, "direct"
end

return adapter