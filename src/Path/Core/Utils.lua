-- Create our Interface
local Interface = {}

-- Table Methods
do
	function Interface.WrapTableIndex(index: number, maximumIndex: number): number
		return (((index - 1) % maximumIndex) + 1)
	end

	function Interface.GetIndexFromScale(scale: number, maximumIndex: number, isRaw: true?): number
		local rawIndex = (1 + ((maximumIndex - 1) * scale))
		return (isRaw and rawIndex or math.floor(rawIndex))
	end

	function Interface.BinarySearch(
		targetValue: number,
		sortedValues: {number}
	): number
		local totalValues = #sortedValues
		local minimum = sortedValues[1]
		local maximum = sortedValues[totalValues]
		if targetValue >= maximum then
			return totalValues
		elseif targetValue <= minimum then
			return 1
		end

		local left, right = 1, totalValues
		while left <= right do
			local mid = ((left + right) // 2)
			local lMid = sortedValues[mid]
			if lMid < targetValue then
				left = (mid + 1)
			elseif lMid > targetValue then
				right = (mid - 1)
			else
				return mid
			end
		end

		return math.max(0, right)
	end
end

-- Iteration Methods
function Interface.GetIterationProgress(iteration: number, totalIterations: number): number
	return math.clamp(
		((iteration - 1) / (totalIterations - 1)),
		0, 1
	)
end

-- Number Methods
function Interface.AssertInRange(value: number): number
	if (value < 0) or (value > 1) then
		error(`Value ({value}) is not in Range [0, 1]`)
	end

	return value
end

-- Interface return
table.freeze(Interface)
return Interface