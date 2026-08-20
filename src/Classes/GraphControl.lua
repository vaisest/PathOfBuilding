-- Path of Building
--
-- Class: Graph Control
-- Draws a stacked area graph of one or more series over a numeric domain.
--
-- The graph spec is a plain table, so calc modules can emit one as breakdown data
-- without pulling in any UI code:
--   xMin, xMax    Domain bounds. May be functions, resolved each frame
--   xScale        "LOG" or "LINEAR" (default)
--   yMin, yMax    Range bounds, default 0 and 100
--   yGuide        Optional value to mark with a dotted horizontal line
--   yFormat       Format string for y values, default "%d%%"
--   xLabel        Optional label drawn under the x axis
--   series        List of { label, color, func(x) }, stacked bottom to top.
--                 func returns the height of that band at x, not the running total
--   markers       List of { x, label }, drawn as dotted vertical lines
--
local ipairs = ipairs
local t_insert = table.insert
local m_max = math.max
local m_min = math.min
local m_ceil = math.ceil
local m_floor = math.floor
local m_huge = math.huge
local m_log10 = math.log10
local s_format = string.format

-- Layout metrics
local PAD_TOP = 8
local PAD_RIGHT = 8
local PAD_BOTTOM = 4
local PAD_LEFT = 30
local TICK_SIZE = 10
local AXIS_LABEL_SIZE = 10
local MARKER_SIZE = 10
local LEGEND_SIZE = 10
local LEGEND_SWATCH = 8
local MAX_SAMPLE_COLS = 400

---@class GraphSeries
---@field label string
---@field color string|number[]
---@field func fun(x: number): number

---@class GraphControl: Control
local GraphControlClass = newClass("GraphControl", "Control")

local function resolve(value)
	if type(value) == "function" then
		return value()
	end
	return value
end

local function setColor(color, alpha)
	if type(color) == "string" then
		SetDrawColor(color)
	elseif alpha then
		SetDrawColor(color[1], color[2], color[3], alpha)
	elseif color[4] then
		SetDrawColor(color[1], color[2], color[3], color[4])
	else
		SetDrawColor(color[1], color[2], color[3])
	end
end

local function formatTick(value)
	if value >= 1000000 then
		return s_format("%gM", round(value / 1000000, 1))
	elseif value >= 1000 then
		return s_format("%gk", round(value / 1000, 1))
	end
	return s_format("%g", round(value, value >= 100 and 0 or 2))
end

function GraphControlClass:GraphControl(anchor, rect, graph)
	self:Control(anchor, rect)
	self:SetGraph(graph)
	return self
end

function GraphControlClass:SetGraph(graph)
	self.graph = graph
	self.cache = nil
	return self
end

function GraphControlClass:XToFrac(x, xMin, xMax, log)
	if log then
		local lo, hi = m_log10(xMin), m_log10(xMax)
		return (m_log10(m_max(x, 1e-6)) - lo) / (hi - lo)
	end
	return (x - xMin) / (xMax - xMin)
end

function GraphControlClass:FracToX(frac, xMin, xMax, log)
	if log then
		local lo, hi = m_log10(xMin), m_log10(xMax)
		return 10 ^ (lo + frac * (hi - lo))
	end
	return xMin + frac * (xMax - xMin)
end

function GraphControlClass:ShowLegend()
	return self.graph.legend ~= false and #self.graph.series > 1
end

-- Area available for the plot itself, excluding axis labels and legend
function GraphControlClass:GetPlotRect()
	local graph = self.graph
	local x, y = self:GetPos()
	local width, height = self:GetSize()
	local reserved = PAD_BOTTOM + TICK_SIZE + 3
	if graph.xLabel then
		reserved = reserved + AXIS_LABEL_SIZE + 1
	end
	if self:ShowLegend() then
		reserved = reserved + LEGEND_SIZE + 3
	end
	return x + PAD_LEFT, y + PAD_TOP, m_max(1, width - PAD_LEFT - PAD_RIGHT), m_max(1, height - PAD_TOP - reserved)
end

-- Sample every series across the domain, once per (width, domain) combination.
-- Draw runs every frame, so this must never happen inline in the draw loop.
function GraphControlClass:Sample(plotW, xMin, xMax)
	local cache = self.cache
	if cache and cache.width == plotW and cache.xMin == xMin and cache.xMax == xMax then
		return cache
	end
	local graph = self.graph
	local log = graph.xScale == "LOG"
	local cols = m_max(2, m_min(m_floor(plotW), MAX_SAMPLE_COLS))
	cache = { width = plotW, xMin = xMin, xMax = xMax, cols = cols, x = { }, series = { }, total = { } }
	for index in ipairs(graph.series) do
		cache.series[index] = { }
	end
	for col = 0, cols do
		local x = self:FracToX(col / cols, xMin, xMax, log)
		cache.x[col] = x
		local total = 0
		for index, series in ipairs(graph.series) do
			local value = series.func(x) or 0
			cache.series[index][col] = value
			total = total + value
		end
		cache.total[col] = total
	end
	self.cache = cache
	return cache
end

function GraphControlClass:DrawDottedLine(x1, y1, x2, y2, dash, gap)
	dash = dash or 2
	gap = gap or 3
	if y1 == y2 then
		local x = x1
		while x < x2 do
			DrawImage(nil, x, y1, m_min(dash, x2 - x), 1)
			x = x + dash + gap
		end
	else
		local y = y1
		while y < y2 do
			DrawImage(nil, x1, y, 1, m_min(dash, y2 - y))
			y = y + dash + gap
		end
	end
end

function GraphControlClass:Draw(viewPort)
	local graph = self.graph
	if not graph or not graph.series or #graph.series == 0 then
		return
	end
	local xMin, xMax = resolve(graph.xMin), resolve(graph.xMax)
	if not xMin or not xMax or xMax <= xMin then
		return
	end
	local log = graph.xScale == "LOG"
	if log and xMin <= 0 then
		xMin = 1
	end
	local yMin = graph.yMin or 0
	local yMax = resolve(graph.yMax) or 100
	local yRange = yMax - yMin
	if yRange <= 0 then
		return
	end
	local yFormat = graph.yFormat or "%d%%"
	local function formatX(value)
		return graph.xFormat and s_format(graph.xFormat, value) or formatTick(value)
	end
	local plotX, plotY, plotW, plotH = self:GetPlotRect()
	local plotBottom = plotY + plotH
	local cache = self:Sample(plotW, xMin, xMax)
	local cols = cache.cols

	-- Plot background
	setColor(graph.bgColor or { 0.12, 0.13, 0.15 })
	DrawImage(nil, plotX, plotY, plotW, plotH)

	-- Stacked areas. Each column is a trapezoid so the top edge follows the curve
	-- instead of stepping; `base` tracks the running stack top for each column.
	local base = { }
	for col = 0, cols do
		base[col] = plotBottom
	end
	for index, series in ipairs(graph.series) do
		local values = cache.series[index]
		setColor(series.color, series.alpha)
		-- Opaque bands overlap by half a pixel so neighbouring quads leave no seam
		local alpha = series.alpha or (type(series.color) == "table" and series.color[4]) or 1
		local overlap = alpha >= 1 and 0.5 or 0
		for col = 0, cols - 1 do
			local x1 = plotX + col / cols * plotW
			local x2 = plotX + (col + 1) / cols * plotW + overlap
			local b1, b2 = base[col], base[col + 1]
			local t1 = m_max(plotY, b1 - values[col] / yRange * plotH)
			local t2 = m_max(plotY, b2 - values[col + 1] / yRange * plotH)
			if b1 - t1 > 0.05 or b2 - t2 > 0.05 then
				DrawImageQuad(nil, x1, t1, x2, t2, x2, b2, x1, b1)
			end
		end
		for col = 0, cols do
			base[col] = m_max(plotY, base[col] - values[col] / yRange * plotH)
		end
	end

	-- Guide line for a cap or other reference value
	local guide = resolve(graph.yGuide)
	local guideY
	if guide and guide >= yMin and guide <= yMax then
		guideY = plotBottom - (guide - yMin) / yRange * plotH
		setColor({ 0.6, 0.6, 0.65 })
		self:DrawDottedLine(plotX, guideY, plotX + plotW, guideY)
		DrawString(plotX - 4, guideY - TICK_SIZE / 2, "RIGHT_X", TICK_SIZE, "VAR", s_format(yFormat, guide))
	end
	-- Top of the scale, unless the guide is already labelled there
	if not guideY or guideY - plotY > TICK_SIZE + 2 then
		SetDrawColor(0.73, 0.73, 0.73)
		DrawString(plotX - 4, plotY, "RIGHT_X", TICK_SIZE, "VAR", s_format(yFormat, yMax))
	end

	-- Markers
	for _, marker in ipairs(graph.markers or { }) do
		local markerX = resolve(marker.x)
		if markerX and markerX == markerX and markerX ~= m_huge and markerX >= xMin and markerX <= xMax then
			local px = plotX + self:XToFrac(markerX, xMin, xMax, log) * plotW
			setColor(marker.color or { 0.85, 0.85, 0.85 })
			self:DrawDottedLine(px, plotY, px, plotBottom)
			if marker.label then
				local labelWidth = DrawStringWidth(MARKER_SIZE, "VAR", marker.label)
				DrawString(m_min(px + 3, plotX + plotW - labelWidth - 2), plotY + 2, "LEFT", MARKER_SIZE, "VAR", marker.label)
			end
		end
	end

	-- Plot border
	setColor({ 0.4, 0.4, 0.45 })
	DrawImage(nil, plotX, plotY, plotW, 1)
	DrawImage(nil, plotX, plotBottom - 1, plotW, 1)
	DrawImage(nil, plotX, plotY, 1, plotH)
	DrawImage(nil, plotX + plotW - 1, plotY, 1, plotH)

	-- X axis ticks
	local ticks = { }
	if log then
		local decade = m_ceil(m_log10(xMin))
		while 10 ^ decade <= xMax do
			t_insert(ticks, 10 ^ decade)
			decade = decade + 1
		end
	else
		for i = 0, 4 do
			t_insert(ticks, xMin + (xMax - xMin) * i / 4)
		end
	end
	local tickY = plotBottom + 3
	SetDrawColor(0.73, 0.73, 0.73)
	for _, tick in ipairs(ticks) do
		local px = plotX + self:XToFrac(tick, xMin, xMax, log) * plotW
		DrawString(px, tickY, "CENTER_X", TICK_SIZE, "VAR", formatX(tick))
	end

	local nextY = tickY + TICK_SIZE + 1
	if graph.xLabel then
		SetDrawColor(0.55, 0.55, 0.55)
		DrawString(plotX + plotW / 2, nextY, "CENTER_X", AXIS_LABEL_SIZE, "VAR", graph.xLabel)
		nextY = nextY + AXIS_LABEL_SIZE + 1
	end

	-- Legend
	if self:ShowLegend() then
		local legendWidth = 0
		for _, series in ipairs(graph.series) do
			legendWidth = legendWidth + LEGEND_SWATCH + 3 + DrawStringWidth(LEGEND_SIZE, "VAR", series.label) + 10
		end
		local legendX = plotX + plotW / 2 - legendWidth / 2
		for _, series in ipairs(graph.series) do
			setColor(series.color)
			DrawImage(nil, legendX, nextY + 1, LEGEND_SWATCH, LEGEND_SWATCH)
			legendX = legendX + LEGEND_SWATCH + 3
			SetDrawColor(0.73, 0.73, 0.73)
			DrawString(legendX, nextY, "LEFT", LEGEND_SIZE, "VAR", series.label)
			legendX = legendX + DrawStringWidth(LEGEND_SIZE, "VAR", series.label) + 10
		end
	end

	-- Hover readout
	local cursorX, cursorY = GetCursorPos()
	if cursorX >= plotX and cursorX < plotX + plotW and cursorY >= plotY and cursorY < plotBottom then
		local col = m_max(0, m_min(cols, round((cursorX - plotX) / plotW * cols)))
		local px = plotX + col / cols * plotW
		local total = cache.total[col]
		local py = m_max(plotY, plotBottom - (total - yMin) / yRange * plotH)
		SetDrawColor(1, 1, 1, 0.5)
		DrawImage(nil, px, plotY, 1, plotH)
		SetDrawColor(1, 1, 1)
		DrawImage(nil, px - 2, py - 2, 5, 5)
		-- Readout sits beside the point, flipping side and clamping so it stays in the plot
		local text = s_format("^7%s ^8-> ^7%s", formatX(cache.x[col]), s_format(yFormat, total))
		local boxWidth = DrawStringWidth(TICK_SIZE, "VAR", StripEscapes(text)) + 6
		local boxHeight = TICK_SIZE + 4
		local boxX = px + 6
		if boxX + boxWidth > plotX + plotW - 2 then
			boxX = px - 6 - boxWidth
		end
		local boxY = m_max(plotY + 2, m_min(py - boxHeight - 4, plotBottom - boxHeight - 2))
		SetDrawColor(0, 0, 0, 0.8)
		DrawImage(nil, boxX, boxY, boxWidth, boxHeight)
		SetDrawColor(1, 1, 1)
		DrawString(boxX + 3, boxY + 2, "LEFT", TICK_SIZE, "VAR", text)
	end
end
