-- Path of Building
--
-- Module: Calc Tools
-- Various functions used by the calculation modules
--
local pairs = pairs
local t_insert = table.insert
local t_remove = table.remove
local m_floor = math.floor
local m_min = math.min
local m_max = math.max

calcLib = { }

-- Calculate and combine INC/MORE modifiers for the given modifier names
function calcLib.mod(modStore, cfg, ...)
	return (1 + (modStore:Sum("INC", cfg, ...)) / 100) * modStore:More(cfg, ...)
end

---Calculates additive and multiplicative modifiers for specified modifier names
---@param modStore table
---@param cfg table
---@param ... string @Mod name(s)
---@return number, number @increased, more
function calcLib.mods(modStore, cfg, ...)
	local inc = 1 + modStore:Sum("INC", cfg, ...) / 100
	local more = modStore:More(cfg, ...)
	return inc, more
end

-- Calculate value
function calcLib.val(modStore, name, cfg)
	local baseVal = modStore:Sum("BASE", cfg, name)
	if baseVal ~= 0 then
		return baseVal * calcLib.mod(modStore, cfg, name)
	else
		return 0
	end
end

-- Validate the level of the given gem
function calcLib.validateGemLevel(gemInstance)
	local grantedEffect = gemInstance.grantedEffect or gemInstance.gemData.grantedEffect
	if not grantedEffect.levels[gemInstance.level] then
		-- Try limiting to the level range of the skill
		gemInstance.level = m_max(1, gemInstance.level)
		if #grantedEffect.levels > 0 then
			gemInstance.level = m_min(#grantedEffect.levels, gemInstance.level)
		end
	end
	if not grantedEffect.levels[gemInstance.level] and gemInstance.gemData and gemInstance.gemData.naturalMaxLevel then
		gemInstance.level = gemInstance.gemData.naturalMaxLevel
	end
	if not grantedEffect.levels[gemInstance.level] then
		-- That failed, so just grab any level
		gemInstance.level = next(grantedEffect.levels)
	end
end

-- Evaluate a skill type postfix expression
function calcLib.doesTypeExpressionMatch(checkTypes, skillTypes, minionTypes)
	local stack = { }
	for _, skillType in pairs(checkTypes) do
		if skillType == SkillType.OR then
			local other = t_remove(stack)
			stack[#stack] = stack[#stack] or other
		elseif skillType == SkillType.AND then
			local other = t_remove(stack)
			stack[#stack] = stack[#stack] and other
		elseif skillType == SkillType.NOT then
			stack[#stack] = not stack[#stack]
		else
			t_insert(stack, skillTypes[skillType] or (minionTypes and minionTypes[skillType]) or false)
		end
	end
	for _, val in ipairs(stack) do
		if val then
			return true
		end
	end
	return false
end

-- Check if given support skill can support the given active skill
---@param appliesToGrantedSkills boolean? Generally modifiers which add support gems to the socketed skills don't work with granted skills, and this flag can be used to mark exceptions such as the Pearl of Tsoatha.
function calcLib.canGrantedEffectSupportActiveSkill(grantedEffect, activeSkill, imbuedSupport, appliesToGrantedSkills)
	if grantedEffect.unsupported or activeSkill.activeEffect.grantedEffect.cannotBeSupported then
		return false
	end
	if grantedEffect.supportGemsOnly and not activeSkill.activeEffect.gemData then
		return false
	end

	-- Special case for things like Forbidden Shako or Hungry Loop with  for example Prismatic Burst and another compatible support
	if not appliesToGrantedSkills and grantedEffect.fromItem and grantedEffect.support and (activeSkill.activeEffect.grantedEffect.fromItem or activeSkill.activeEffect.grantedEffect.modSource:sub(1, #"Item") == "Item" or (activeSkill.activeEffect.srcInstance and activeSkill.activeEffect.srcInstance.fromItem)) then
		return false
	end

	local effectiveSkillTypes
	local effectiveMinionTypes
	if imbuedSupport then -- Use the skillTypes from the gem so it ignores any support added types
		effectiveSkillTypes = activeSkill.summonSkill and activeSkill.summonSkill.activeEffect.grantedEffect.skillTypes or activeSkill.activeEffect.grantedEffect.skillTypes
		effectiveMinionTypes = not grantedEffect.ignoreMinionTypes and (activeSkill.summonSkill and activeSkill.summonSkill.activeEffect.grantedEffect.minionSkillTypes or activeSkill.activeEffect.grantedEffect.minionSkillTypes)
	else
		effectiveSkillTypes = activeSkill.summonSkill and activeSkill.summonSkill.skillTypes or activeSkill.skillTypes
		effectiveMinionTypes = not grantedEffect.ignoreMinionTypes and (activeSkill.summonSkill and activeSkill.summonSkill.minionSkillTypes or activeSkill.minionSkillTypes)
	end

	-- if the activeSkill is a Minion's skill like "Default Attack", use minion's skillTypes instead for exclusions
	-- otherwise compare support to activeSkill directly
	if grantedEffect.excludeSkillTypes[1] and calcLib.doesTypeExpressionMatch(grantedEffect.excludeSkillTypes, effectiveSkillTypes) then
		return false
	end
	if grantedEffect.isTrigger and activeSkill.actor.enemy.player ~= activeSkill.actor then
		return false
	end
	-- Special case for Sacred Wisps, i.e. Wisps Support has a weaponType of Wand so it should only match with Active Skills that at least have Wand as a weaponType.
	-- Super special case for Varunastra, e.g. allow Nightblade to support Smite.
	local actorHasAllOneHand = (activeSkill.actor.weaponData1 and activeSkill.actor.weaponData1.countsAsAll1H) or (activeSkill.actor.weaponData2 and activeSkill.actor.weaponData2.countsAsAll1H)
	if grantedEffect.weaponTypes then
		-- Build a lookup of the active skill's weapon types
		local activeTypeLookup = { }
		if activeSkill.activeEffect.grantedEffect.weaponTypes then
			for activeType in pairs(activeSkill.activeEffect.grantedEffect.weaponTypes) do
				activeTypeLookup[activeType] = true
			end
		elseif effectiveSkillTypes[SkillType.SkillGrantedBySupport] then
			-- Skills granted by supports do not have their own weaponTypes, so check the equipped weapons instead.
			if activeSkill.actor.weaponData1.type then
				activeTypeLookup[activeSkill.actor.weaponData1.type] = true
			end
			if activeSkill.actor.weaponData2.type then
				activeTypeLookup[activeSkill.actor.weaponData2.type] = true
			end
		end
		-- If the support expects a weapon type but the active skill doesn't have any (e.g. shield skills), it's not a match.
		if not next(activeTypeLookup) then
			return false
		end
		-- Varunastra counts as every one-handed melee weapon type, but notably not Wand or Shield.
		if actorHasAllOneHand then
			activeTypeLookup["Claw"] = true
			activeTypeLookup["Dagger"] = true
			activeTypeLookup["One Handed Axe"] = true
			activeTypeLookup["One Handed Mace"] = true
			activeTypeLookup["One Handed Sword"] = true
		end
		local typeMatch = false
		for grantedType in pairs(grantedEffect.weaponTypes) do
			if activeTypeLookup[grantedType] then
				typeMatch = true
				break
			end
		end
		-- No match, does not support the active skill
		if not typeMatch then
			return false
		end
	end
	return not grantedEffect.requireSkillTypes[1] or calcLib.doesTypeExpressionMatch(grantedEffect.requireSkillTypes, effectiveSkillTypes, effectiveMinionTypes)
end

-- Check if given gem is of the given type ("all", "strength", "melee", etc)
function calcLib.gemIsType(gem, type, includeTransfigured)
	return (type == "all" or 
			(type == "elemental" and (gem.tags.fire or gem.tags.cold or gem.tags.lightning)) or 
			(type == "aoe" and gem.tags.area) or
			(type == "trap or mine" and (gem.tags.trap or gem.tags.mine)) or
			((type == "active skill" or type == "grants_active_skill" or type == "skill") and gem.tags.grants_active_skill and not gem.tags.support) or
			(type == "non-vaal" and not gem.tags.vaal) or
			(type == "non-exceptional" and not gem.tags.exceptional) or
			(type == gem.name:lower()) or
			(type == gem.name:lower():gsub("^vaal ", "")) or
			(includeTransfigured and calcLib.isGemIdSame(gem.name, type, true)) or
			((type ~= "active skill" and type ~= "grants_active_skill" and type ~= "skill") and gem.tags[type]))
end

-- In-game formula
function calcLib.getGemStatRequirement(level, isSupport, multi)
	if multi == 0 then
		return 0
	end
	local statType = 0.7
	if isSupport then
		statType = 0.5
	end
	local req = round( ( 20 + ( level - 3 ) * 3 ) * ( multi / 100 ) ^ 0.9 * statType )
	return req < 14 and 0 or req
end

-- Build table of stats for the given skill instance
function calcLib.buildSkillInstanceStats(skillInstance, grantedEffect)
	local stats = { }
	if skillInstance.quality > 0 and grantedEffect.qualityStats then
		local qualityStats = grantedEffect.qualityStats
		for _, stat in ipairs(qualityStats) do
			stats[stat[1]] = (stats[stat[1]] or 0) + math.modf(stat[2] * skillInstance.quality)
		end
	end
	local level = grantedEffect.levels[skillInstance.level] or { }
	local availableEffectiveness
	local actorLevel = skillInstance.actorLevel or level.levelRequirement or 1
	for index, stat in ipairs(grantedEffect.stats) do
		-- Static value used as default (assumes statInterpolation == 1)
		local statValue = level[index] or 1
		if level.statInterpolation then
			if level.statInterpolation[index] == 3 then
				-- Effectiveness interpolation
				if not availableEffectiveness then
					availableEffectiveness =
					(data.gameConstants["SkillDamageBaseEffectiveness"] + data.gameConstants["SkillDamageIncrementalEffectiveness"] * (actorLevel - 1)) * (grantedEffect.baseEffectiveness or 1)
							* (1 + (grantedEffect.incrementalEffectiveness or 0)) ^ (actorLevel - 1)
				end
				statValue = round(availableEffectiveness * level[index])
			elseif level.statInterpolation[index] == 2 then
				-- Linear interpolation; I'm actually just guessing how this works

				-- Order the levels, since sometimes they skip around
				local orderedLevels = { }
				local currentLevelIndex
				for level, _ in pairs(grantedEffect.levels) do
					t_insert(orderedLevels, level)
				end
				table.sort(orderedLevels)
				for idx, level in ipairs(orderedLevels) do
					if skillInstance.level == level then
						currentLevelIndex = idx
					end
				end

				if #orderedLevels > 1 then
					local nextLevelIndex = m_min(currentLevelIndex + 1, #orderedLevels)
					local nextReq = grantedEffect.levels[orderedLevels[nextLevelIndex]].levelRequirement
					local prevReq = grantedEffect.levels[orderedLevels[nextLevelIndex - 1]].levelRequirement
					local nextStat = grantedEffect.levels[orderedLevels[nextLevelIndex]][index]
					local prevStat = grantedEffect.levels[orderedLevels[nextLevelIndex - 1]][index]
					statValue = round(prevStat + (nextStat - prevStat) * (actorLevel - prevReq) / (nextReq - prevReq))
				else
					statValue = round(grantedEffect.levels[orderedLevels[currentLevelIndex]][index])
				end
			end
		end
		stats[stat] = (stats[stat] or 0) + statValue
	end
	if grantedEffect.constantStats then
		for _, stat in ipairs(grantedEffect.constantStats) do
			stats[stat[1]] = (stats[stat[1]] or 0) + (stat[2] or 0)
		end
	end
	return stats
end

--- Correct the tags on conversion with multipliers so they carry over correctly
--- @param mod table
--- @param multiplier number
--- @param minionMods boolean @convert ActorConditions pointing at parent to normal Conditions
--- @return table @converted multipliers
function calcLib.getConvertedModTags(mod, multiplier, minionMods)
	local modifiers = { }
	for k, value in ipairs(mod) do
		if minionMods and value.type == "ActorCondition" and value.actor == "parent" then
			modifiers[k] = { type = "Condition", var = value.var }
		elseif value.limitTotal then
			-- LimitTotal can apply to 'per stat' or 'multiplier', so just copy the whole and update the limit
			local copy = copyTable(value)
			copy.limit = copy.limit * multiplier
			modifiers[k] = copy
		else
			modifiers[k] = copyTable(value)
		end
	end
	return modifiers
end

--- Get the gameId from the gemName which will be the same as the base gem for transfigured gems
--- @param gemName string
--- @param dropVaal boolean
--- @return string
function calcLib.getGameIdFromGemName(gemName, dropVaal)
	if type(gemName) ~= "string" then
		return
	end
	local gemId = data.gemForBaseName[gemName:lower()]
	if not gemId then return end
	local gameId 
	if dropVaal and data.gems[gemId].vaalGem then
		gameId = data.gems[data.gemVaalGemIdForBaseGemId[gemId]].gameId
	else
		gameId = data.gems[gemId].gameId
	end
	return gameId
end

--- Use getGameIdFromGemName to get gameId from the gemName and passed in type. Return true if they're the same and not nil
--- @param gemName string
--- @param typeName string
--- @param dropVaal boolean 
--- @return boolean
function calcLib.isGemIdSame(gemName, typeName, dropVaal)
	local gemNameId = calcLib.getGameIdFromGemName(gemName, dropVaal)
	local typeId = calcLib.getGameIdFromGemName(typeName, dropVaal)
	return gemNameId and typeId and gemNameId == typeId
end

-- Spark projectiles wander randomly, bounce off walls and expire when too far from the character.
-- The sparks of a cast can hit a given enemy once, but forget which enemies they hit every 0.66 seconds.
-- Sparks that hit are destroyed unless they pierce.
-- Hits are estimated by simulating casts with a fixed random seed, so the result is stable between calculations.
-- The simulation uses FFI arrays and a bit-based random number generator so LuaJIT can compile it to tight machine code.
local ffi = require("ffi")
local bxor, lshift, rshift = bit.bxor, bit.lshift, bit.rshift
local m_sqrt, m_sin, m_cos = math.sqrt, math.sin, math.cos

local sparkSpeed = 80 -- units per second, measured from gameplay footage
local sparkRadius = 1.5
local sparkMaxDistance = 150 -- sparks are destroyed when they get this far from the character
local sparkHitListClearInterval = 0.66
local sparkWander = 1 -- standard deviation of random turning in radians per sqrt(second), assumed
local sparkSimulatedCasts = 1000 -- gives roughly 2% precision in about 3ms
-- Turning is looked up from a table of precomputed rotations instead of calling sin and cos every tick
local sparkTurnSteps = 256
local sparkTurnCos = ffi.new("double[?]", sparkTurnSteps)
local sparkTurnSin = ffi.new("double[?]", sparkTurnSteps)
-- Per-spark state, reused between simulations and grown when a cast has more sparks than before
local sparkCapacity = 0
local sparkX, sparkY, sparkDirX, sparkDirY, sparkLives
-- Results keyed by the simulation inputs, as most recalculations don't change any of them
local sparkCache = { }
local sparkCacheSize = 0

---Simulates Spark casts from the origin towards an enemy on the x axis
---@param spread number angle in radians the sparks are launched over, centred on the enemy
---@param arenaRadius number? radius of the circular arena centred on the character, or nil for an open area
---@return number averageHits
local function simulateSparkHits(projCount, pierce, duration, speed, reach, distance, arenaRadius, spread)
	if projCount > sparkCapacity then
		sparkCapacity = projCount
		sparkX = ffi.new("double[?]", projCount)
		sparkY = ffi.new("double[?]", projCount)
		sparkDirX = ffi.new("double[?]", projCount)
		sparkDirY = ffi.new("double[?]", projCount)
		sparkLives = ffi.new("double[?]", projCount)
	end
	-- Sparks move once per server tick, like they do in game
	local tickTime = data.misc.ServerTickTime
	-- Uniformly distributed turn with the same variance as normally distributed wander
	local maxTurn = sparkWander * m_sqrt(3 * tickTime)
	for i = 0, sparkTurnSteps - 1 do
		local angle = ((i + 0.5) / sparkTurnSteps * 2 - 1) * maxTurn
		sparkTurnCos[i], sparkTurnSin[i] = m_cos(angle), m_sin(angle)
	end
	-- Restarting from the same seed makes every calculation see the same random sparks, so builds compare consistently
	local seed = 0x2545F491
	local stepLength = speed * tickTime
	-- Sparks expire before reaching walls further away than their maximum distance
	local arena = m_min(arenaRadius or sparkMaxDistance, sparkMaxDistance)
	local arenaSq = arena * arena
	local reachSq = reach * reach
	local ticks = m_floor(duration / tickTime)
	local totalHits = 0
	for _ = 1, sparkSimulatedCasts do
		-- Launch every spark from the character in a random direction within the spread
		for i = 0, projCount - 1 do
			-- xorshift32 random number generator
			seed = bxor(seed, lshift(seed, 13))
			seed = bxor(seed, rshift(seed, 17))
			seed = bxor(seed, lshift(seed, 5))
			-- bit operations return signed 32-bit numbers, so convert to a number between 0 and 1 first
			local angle = (seed % 4294967296 / 4294967296 - 0.5) * spread
			sparkX[i], sparkY[i] = 0, 0
			sparkDirX[i], sparkDirY[i] = m_cos(angle), m_sin(angle)
			sparkLives[i] = 1 + pierce
		end
		local alive = projCount
		-- The hit list window in which the enemy was last hit; it can't be hit again until the next window
		local lastHitWindow = -1
		for tick = 1, ticks do
			if alive == 0 then
				break
			end
			local window = m_floor(tick * tickTime / sparkHitListClearInterval)
			for i = 0, projCount - 1 do
				if sparkLives[i] > 0 then
					-- Turn the spark by a random angle, using the top 8 bits of the random number as the table index
					seed = bxor(seed, lshift(seed, 13))
					seed = bxor(seed, rshift(seed, 17))
					seed = bxor(seed, lshift(seed, 5))
					local turn = rshift(seed, 24)
					local turnCos, turnSin = sparkTurnCos[turn], sparkTurnSin[turn]
					local dirX, dirY = sparkDirX[i], sparkDirY[i]
					dirX, dirY = dirX * turnCos - dirY * turnSin, dirX * turnSin + dirY * turnCos
					local oldX, oldY = sparkX[i], sparkY[i]
					local x, y = oldX + dirX * stepLength, oldY + dirY * stepLength
					local distSq = x * x + y * y
					-- Bounce off the arena wall by mirroring the direction around the wall's normal
					if arenaRadius and distSq > arenaSq then
						local dist = m_sqrt(distSq)
						local normalX, normalY = x / dist, y / dist
						local dot = dirX * normalX + dirY * normalY
						dirX, dirY = dirX - 2 * dot * normalX, dirY - 2 * dot * normalY
						x, y = normalX * arena, normalY * arena
						distSq = arenaSq
					end
					sparkDirX[i], sparkDirY[i] = dirX, dirY
					sparkX[i], sparkY[i] = x, y
					if distSq > sparkMaxDistance * sparkMaxDistance then
						sparkLives[i] = 0
						alive = alive - 1
					elseif window ~= lastHitWindow then
						-- Check whether the step from the old to the new position touched the enemy.
						-- Sparks can move further than the enemy's size in one tick, so checking only the new position would miss hits.
						-- Solves |old + t * move - enemy| = reach for t, where the step touches the enemy if 0 <= t <= 1
						local moveX, moveY = x - oldX, y - oldY
						local offsetX, offsetY = oldX - distance, oldY
						local a = moveX * moveX + moveY * moveY
						local b = 2 * (moveX * offsetX + moveY * offsetY)
						local c = offsetX * offsetX + offsetY * offsetY - reachSq
						-- Sparks already overlapping the enemy hit as soon as the hit list clears
						local hit = c <= 0
						if not hit then
							local discriminant = b * b - 4 * a * c
							if discriminant >= 0 then
								local entry = (-b - m_sqrt(discriminant)) / (2 * a)
								hit = entry >= 0 and entry <= 1
							end
						end
						if hit then
							totalHits = totalHits + 1
							lastHitWindow = window
							-- Each pierce lets the spark survive one more hit
							sparkLives[i] = sparkLives[i] - 1
							if sparkLives[i] <= 0 then
								alive = alive - 1
							end
						end
					end
				end
			end
		end
	end
	return totalHits / sparkSimulatedCasts
end

---Estimates the average and maximum number of times one Spark cast hits a single enemy
---@param spreadAngle number angle in degrees the sparks are launched over
---@return number averageHits, number maximumHits
function calcLib.sparkHitsPerCast(activeSkill, output, breakdown, spreadAngle)
	local skillData = activeSkill.skillData
	local skillModList, skillCfg = activeSkill.skillModList, activeSkill.skillCfg
	local projCount = output.ProjectileCount
	local pierce = output.PierceCount or 0
	local duration = output.Duration
	local speed = sparkSpeed * output.ProjectileSpeedMod
	local enemyRadius = skillModList:Override(skillCfg, "EnemyRadius") or skillModList:Sum("BASE", skillCfg, "EnemyRadius")
	local reach = enemyRadius + sparkRadius
	local distance = m_max(skillData.sparkEnemyDistance or 40, 1)
	local arenaRadius = skillData.sparkArenaRadius
	local travelTime = m_max(distance - reach, 0) / speed
	-- Sparks can't reach the enemy before expiring
	if projCount < 1 or travelTime >= duration or distance - reach > sparkMaxDistance then
		return 0, 0
	end
	-- One hit is possible in each hit list window the sparks are alive for after reaching the enemy
	local firstWindow = m_floor(travelTime / sparkHitListClearInterval)
	local lastWindow = m_floor((duration - 1e-6) / sparkHitListClearInterval)
	local maxHits = m_min(lastWindow - firstWindow + 1, projCount * (1 + pierce))

	-- The key holds every input the simulation depends on
	local key = string.format("%d|%g|%g|%g|%g|%g|%g|%g", projCount, pierce, duration, speed, reach, distance, arenaRadius or 0, spreadAngle)
	local hits = sparkCache[key]
	if not hits then
		-- Start over when the cache gets large instead of tracking which entries are still in use
		if sparkCacheSize >= 1000 then
			wipeTable(sparkCache)
			sparkCacheSize = 0
		end
		hits = simulateSparkHits(projCount, pierce, duration, speed, reach, distance, arenaRadius, math.rad(spreadAngle))
		sparkCache[key] = hits
		sparkCacheSize = sparkCacheSize + 1
	end

	if breakdown then
		breakdown.SparkHitsPerCast = {
			string.format("^8Simulated^7 %d ^8casts of^7 %d ^8sparks travelling^7 %d ^8units/s", sparkSimulatedCasts, projCount, speed),
			string.format("^8Enemy with^7 %d ^8radius^7 %d ^8units away, %s", enemyRadius, distance, arenaRadius and string.format("in a^7 %d ^8radius arena", arenaRadius) or "in an open area"),
			string.format("^8Average hits per cast:^7 %.3f", hits),
			string.format("^8Maximum hits (one per^7 %.2fs ^8hit list window, limited by sparks and pierce):^7 %d", sparkHitListClearInterval, maxHits),
		}
	end
	return hits, maxHits
end
