describe("TestBreakdownGraphs", function()
	before_each(function()
		newBuild()
		build.configTab.input.customMods = "\z
		+2000 to Armour\n\z
		+2000 to Evasion Rating\n\z
		+200 to all Resistances\n\z
		20% additional Physical Damage Reduction\n\z
		"
		build.configTab:BuildModList()
		runCallback("OnFrame")
	end)

	local function breakdownOf(stat)
		return build.calcsTab.calcsEnv.player.breakdown[stat]
	end

	local function outputOf(stat)
		return build.calcsTab.calcsEnv.player.output[stat]
	end

	describe("evade chance", function()
		it("emits a graph whose curve matches the calculated evade chance", function()
			local graph = breakdownOf("EvadeChance").graph
			assert.is_not_nil(graph)
			assert.are.equals("LOG", graph.xScale)
			assert.are.equals(1, #graph.series)

			local enemyAccuracy = graph.markers[1].x
			assert.are.equals("Enemy", graph.markers[1].label)
			assert.are.equals(round(outputOf("EvadeChance"), 4), round(graph.series[1].func(enemyAccuracy), 4))
		end)

		it("falls off as enemy accuracy rises and stays within the cap", function()
			local graph = breakdownOf("MeleeEvadeChance").graph
			local func = graph.series[1].func
			local previous = 101
			for accuracy = graph.xMin, graph.xMax, (graph.xMax - graph.xMin) / 40 do
				local value = func(accuracy)
				assert.is_true(value <= data.misc.EvadeChanceCap)
				assert.is_true(value >= 0)
				assert.is_true(value <= previous)
				previous = value
			end
		end)
	end)

	describe("physical damage reduction", function()
		it("emits stacked armour and base bands that sum to the calculated reduction", function()
			local graph = breakdownOf("PhysicalDamageReduction").graph
			assert.is_not_nil(graph)
			assert.are.equals(2, #graph.series)
			assert.are.equals("Armour", graph.series[1].label)
			assert.are.equals("Base", graph.series[2].label)

			local enemyHit = graph.markers[1].x
			local total = graph.series[1].func(enemyHit) + graph.series[2].func(enemyHit)
			-- The graph uses the unrounded armour formula, so allow for the rounding in the output
			assert.is_true(math.abs(total - outputOf("PhysicalDamageReduction")) < 1)
		end)

		it("keeps the stack under the reduction cap at every hit size", function()
			local graph = breakdownOf("PhysicalDamageReduction").graph
			local cap = outputOf("DamageReductionMax")
			local armourBand, baseBand = graph.series[1].func, graph.series[2].func
			local previousArmour = cap + 1
			for _, hit in ipairs({ 10, 100, 500, 1000, 5000, 20000, 100000 }) do
				local armour, base = armourBand(hit), baseBand(hit)
				assert.is_true(armour >= 0 and base >= 0)
				assert.is_true(armour + base <= cap)
				assert.is_true(armour <= previousArmour)
				previousArmour = armour
			end
			-- Armour is worthless against a huge hit, leaving only the flat reduction
			assert.are.equals(0, round(armourBand(1e9), 2))
			assert.are.equals(20, round(baseBand(1e9), 2))
		end)

		it("resolves the max hit marker lazily, after the full calc pass", function()
			local graph = breakdownOf("PhysicalDamageReduction").graph
			local marker = graph.markers[2]
			assert.are.equals("Max hit", marker.label)
			assert.are.equals("function", type(marker.x))
			assert.is_true(marker.x() > 0)
		end)
	end)

	describe("resistance", function()
		it("plots damage taken as a multiple of the damage taken at the cap", function()
			local graph = breakdownOf("FireResist").graph
			assert.is_not_nil(graph)
			assert.are.equals(1, graph.yGuide)
			assert.are.equals(1, #graph.series)

			local maxResist = outputOf("FireResist") + outputOf("MissingFireResist")
			assert.are.equals(75, maxResist)
			-- At the cap you are, by definition, taking 1x your damage taken at the cap
			assert.are.equals(1, graph.series[1].func(maxResist))
		end)

		-- No armour applies to fire here, so the multiplier is just the ratio of the
		-- taken multipliers, including the enemy penetration the calc is configured with
		local function expectedMultiplier(resist)
			local pen = build.calcsTab.calcsEnv.player.output.FireEnemyPen or 0
			return (100 - resist + pen) / (100 - 75 + pen)
		end

		it("runs past the character's max resistance up to the hard cap", function()
			local graph = breakdownOf("FireResist").graph
			assert.are.equals(data.misc.MaxResistCap, graph.xMax)
			assert.are.equals(90, graph.xMax)
			assert.are.equals(round(expectedMultiplier(90), 4), round(graph.series[1].func(90), 4))
			-- Raising max resistance to the hard cap more than halves the damage taken
			assert.is_true(graph.series[1].func(90) < 0.5)
		end)

		it("shows what a few missing percent costs", function()
			local func = breakdownOf("FireResist").graph.series[1].func
			assert.are.equals(round(expectedMultiplier(73), 4), round(func(73), 4))
			assert.are.equals(round(expectedMultiplier(70), 4), round(func(70), 4))
			-- Being 2% short of the cap costs more than 5% extra damage taken, 5% short over 15%
			assert.is_true(func(73) > 1.05)
			assert.is_true(func(70) > 1.15)
		end)

		it("rises monotonically as resistance drops", function()
			local graph = breakdownOf("FireResist").graph
			local func = graph.series[1].func
			local previous = 0
			for resist = graph.xMax, graph.xMin, -1 do
				local value = func(resist)
				assert.is_true(value >= previous)
				assert.is_true(value <= graph.yMax)
				previous = value
			end
			assert.are.equals("Current", graph.markers[1].label)
			assert.are.equals(outputOf("FireResist"), graph.markers[1].x)
		end)

		it("is not emitted for physical damage, which has no resistance", function()
			assert.is_nil(breakdownOf("PhysicalResist"))
		end)
	end)

	describe("graph control", function()
		local function newGraphControl(graph)
			local control = new("GraphControl"):GraphControl(nil, { 0, 0, 320, 150 }, graph)
			control.x, control.y = 0, 0
			return control
		end

		it("samples every series across the domain and caches the result", function()
			local graph = breakdownOf("PhysicalDamageReduction").graph
			local control = newGraphControl(graph)
			local cache = control:Sample(280, 100, 100000)
			assert.are.equals(280, cache.cols)
			assert.are.equals(2, #cache.series)
			for col = 0, cache.cols do
				assert.are.equals(cache.series[1][col] + cache.series[2][col], cache.total[col])
			end
			assert.are.equals(cache, control:Sample(280, 100, 100000))
			assert.are_not.equals(cache, control:Sample(280, 100, 50000))
		end)

		it("maps the log domain to fractions and back", function()
			local control = newGraphControl(breakdownOf("EvadeChance").graph)
			assert.are.equals(0.5, control:XToFrac(100, 10, 1000, true))
			assert.are.equals(100, round(control:FracToX(0.5, 10, 1000, true), 6))
			assert.are.equals(0.25, control:XToFrac(250, 0, 1000, false))
		end)

		it("draws without a cursor over it and with one", function()
			local control = newGraphControl(breakdownOf("PhysicalDamageReduction").graph)
			local viewPort = { x = 0, y = 0, width = 1920, height = 1080 }
			control:Draw(viewPort)

			local realGetCursorPos = GetCursorPos
			GetCursorPos = function() return 150, 40 end
			local ok, err = pcall(function() control:Draw(viewPort) end)
			GetCursorPos = realGetCursorPos
			assert.is_true(ok, tostring(err))
		end)
	end)
end)
