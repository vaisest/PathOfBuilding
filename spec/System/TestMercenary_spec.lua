describe("TestMercenary", function()
	before_each(function()
		newBuild()
	end)

	local function addGroup(mercenary, ...)
		local group = { label = "", enabled = true, mercenary = mercenary, gemList = { } }
		for _, gemId in ipairs({ ... }) do
			local gemData = build.data.gems[gemId]
			table.insert(group.gemList, { gemId = gemId, nameSpec = gemData.name, skillId = gemData.grantedEffectId, level = gemData.naturalMaxLevel, quality = 0, enabled = true, enableGlobal1 = true, count = 1 })
		end
		build.skillsTab:ProcessSocketGroup(group)
		table.insert(build.skillsTab.socketGroupList, group)
		build.buildFlag = true
		runCallback("OnFrame")
	end

	local function addMercenaryGroup(...)
		local gemIds = { }
		for _, skillId in ipairs({ ... }) do
			table.insert(gemIds, "Mercenary/"..skillId)
		end
		addGroup(true, unpack(gemIds))
	end

	local function hireMercenary()
		addGroup(false, "Metadata/Items/Gems/SkillGemCallMercenary")
		build.mainSocketGroup = #build.skillsTab.socketGroupList
		build.buildFlag = true
		runCallback("OnFrame")
		return build.calcsTab.mainEnv.player.mainSkill.minion
	end

	it("has selectable mercenary gems that don't replace player gems", function()
		local gemData = build.data.gems["Mercenary/SparkMercenary"]
		assert.are.equals("Spark", gemData.name)
		assert.is_true(gemData.tags.mercenary)
		assert.are.equals("Spark", build.data.gems[build.data.gemForBaseName["spark"]].grantedEffect.id)
		-- Implementation is inherited from the player skill
		assert.are.same(build.data.skills.Spark.baseFlags, build.data.skills.SparkMercenary.baseFlags)
	end)

	it("grants Order: To me! from Noble Blood", function()
		local mods = modLib.parseMod("You can hire a Mercenary permanently")
		assert.are.equals("ExtraSkill", mods[1].name)
		assert.are.equals("CallMercenary", mods[1].value.skillId)
	end)

	it("uses mercenary skills and supports on the mercenary instead of the player", function()
		addMercenaryGroup("SparkMercenary", "MercenarySupportMultipleProjectilesHigh")
		local minion = hireMercenary()
		assert.are.equals("Mercenary", minion.minionData.name)
		local mercSkill = minion.activeSkillList[1]
		assert.are.equals("SparkMercenary", mercSkill.activeEffect.grantedEffect.id)
		assert.are.equals(2, #mercSkill.effectList)
		assert.are.equals("MercenarySupportMultipleProjectilesHigh", mercSkill.effectList[2].grantedEffect.id)
		assert.is_true(build.calcsTab.mainOutput.Minion.TotalDPS > 0)
		for _, activeSkill in ipairs(build.calcsTab.mainEnv.player.activeSkillList) do
			assert.is_nil(activeSkill.activeEffect.grantedEffect.mercenary)
		end
	end)

	it("uses the configured mercenary level for skill levels instead of the gem level", function()
		addMercenaryGroup("SparkMercenary")
		build.skillsTab.socketGroupList[1].gemList[1].level = 1
		build.configTab.input.mercenaryLevel = 70
		build.configTab:BuildModList()
		local minion = hireMercenary()
		assert.are.equals(70, minion.level)
		local expectedLevel = 1
		for level, levelData in ipairs(build.data.skills.SparkMercenary.levels) do
			if levelData.levelRequirement <= minion.level then
				expectedLevel = level
			end
		end
		assert.is_true(expectedLevel > 1)
		assert.are.equals(expectedLevel, minion.activeSkillList[1].activeEffect.level)
	end)

	it("has the permanent mercenary damage penalty tapering in with level", function()
		addMercenaryGroup("SparkMercenary")
		local function penalty(level)
			build.configTab.input.mercenaryLevel = level
			build.configTab:BuildModList()
			for _, value in ipairs(hireMercenary().modDB:Tabulate("MORE", nil, "Damage")) do
				if value.mod.source == "Permanent Mercenary" then
					return value.mod.value
				end
			end
			return 0
		end
		assert.are.equals(84, hireMercenary().level)
		assert.are.equals(-30, penalty(84))
		assert.are.equals(-15, penalty(64))
		assert.are.equals(0, penalty(45))
	end)

	it("gets Luminary mercenary modifiers, but other minions don't", function()
		addMercenaryGroup("SparkMercenary")
		build.configTab.input.customMods = "Your Mercenary and their Minions deal 15% increased Damage"
		build.configTab:BuildModList()
		local minion = hireMercenary()
		assert.are.equals(15, minion.modDB:Sum("INC", nil, "Damage"))
		addGroup(false, "Metadata/Items/Gems/SkillGemSummonRagingSpirit")
		build.mainSocketGroup = #build.skillsTab.socketGroupList
		build.buildFlag = true
		runCallback("OnFrame")
		assert.are.equals(0, build.calcsTab.mainEnv.player.mainSkill.minion.modDB:Sum("INC", nil, "Damage"))
	end)

	it("gets the hidden stats of its mercenary type", function()
		addMercenaryGroup("IceShotMercenary")
		local function hiddenDamage(level, buildId)
			build.configTab.input.mercenaryLevel = level
			build.configTab.input.mercenaryBuild = buildId
			build.configTab:BuildModList()
			for _, value in ipairs(hireMercenary().modDB:Tabulate("INC", nil, "Damage")) do
				if value.mod.source:match("^Mercenary:") then
					return value.mod.source, value.mod.value
				end
			end
		end
		assert.are.same({ "Mercenary:Manyshot", 250 }, { hiddenDamage(84, "AUTO") })
		assert.are.same({ "Mercenary:Manyshot", 225 }, { hiddenDamage(76, "AUTO") })
		assert.are.same({ "Mercenary:Manyshot", 100 }, { hiddenDamage(10, "AUTO") })
		assert.are.equals("Mercenary:Flamequiver", (hiddenDamage(84, "EleBowRangerFire")))
	end)

	it("searches the supports of a mercenary skill while typing", function()
		addMercenaryGroup("HydraForkArrowMercenary")
		build.skillsTab:SetDisplayGroup(build.skillsTab.socketGroupList[1])
		local control = build.skillsTab.gemSlots[2].nameSpec
		control.hasFocus = true
		for char in ("hypothermia"):gmatch(".") do
			control:OnChar(char)
		end
		local names = { }
		for _, gemId in ipairs(control.list) do
			table.insert(names, control.gems[gemId].name)
		end
		table.sort(names)
		assert.are.same({ "Greater Hypothermia", "Hypothermia", "Lesser Hypothermia" }, names)
	end)

	it("saves and loads mercenary socket groups", function()
		addMercenaryGroup("SparkMercenary", "MercenarySupportMultipleProjectilesHigh")
		loadBuildFromXML(build:SaveDB("code"))
		local group = build.skillsTab.socketGroupList[1]
		assert.is_true(group.mercenary)
		assert.are.equals("Mercenary/SparkMercenary", group.gemList[1].gemData.id)
		assert.are.equals("Mercenary/MercenarySupportMultipleProjectilesHigh", group.gemList[2].gemData.id)
	end)

	it("applies mercenary auras to the player", function()
		addMercenaryGroup("WrathMercenary")
		hireMercenary()
		assert.is_true(build.calcsTab.mainEnv.player.modDB.conditions["AffectedByWrath"])
	end)

	it("can be linked without link skills targeting minions", function()
		addMercenaryGroup("SparkMercenary")
		addGroup(false, "Metadata/Items/Gems/SkillGemFlameLink")
		build.configTab.input.linkedToMinion = true
		build.configTab:BuildModList()
		local minion = hireMercenary()
		assert.is_true(minion.modDB.conditions["AffectedByFlameLink"])
	end)

	it("applies light radius to link effect on the mercenary with Golden Glory", function()
		addMercenaryGroup("SparkMercenary")
		addGroup(false, "Metadata/Items/Gems/SkillGemFlameLink")
		build.configTab.input.linkedToMinion = true
		local function linkedFireMax(customMods)
			build.configTab.input.customMods = customMods
			build.configTab:BuildModList()
			return hireMercenary().modDB:Sum("BASE", nil, "FireMax")
		end
		local base = linkedFireMax("")
		assert.is_true(base > 0)
		assert.are.equals(base, linkedFireMax("50% increased Light Radius"))
		assert.is_true(linkedFireMax("50% increased Light Radius\nIncreases and Reductions to Light Radius also apply to Effect of your Link Skill Buffs on your Mercenary") > base)
	end)

	it("gets character-like base life and gear from its item set", function()
		addMercenaryGroup("SparkMercenary")
		local minion = hireMercenary()
		local baseLife = build.calcsTab.mainOutput.Minion.Life
		assert.are.equals(18 * minion.level, baseLife)

		local itemSet = build.itemsTab:NewItemSet()
		table.insert(build.itemsTab.itemSetOrderList, itemSet.id)
		local item = new("Item"):Item([[
			Rarity: RARE
			Test Subject
			Iron Hat
			+50 to maximum Life
		]])
		build.itemsTab:AddItem(item)
		itemSet["Helmet"].selItemId = item.id
		build.skillsTab.socketGroupList[build.mainSocketGroup].gemList[1].skillMinionItemSet = itemSet.id
		build.buildFlag = true
		runCallback("OnFrame")
		assert.are.equals(baseLife + 50, build.calcsTab.mainOutput.Minion.Life)
	end)
end)
