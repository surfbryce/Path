-- Our Modules
local LUT = require(script.LUT)

-- Our Types
export type Gauss = {{number}}

-- Logic
local minimumOrder = 5
local maximumOrder = (minimumOrder + #LUT)
return function(order: number): Gauss
	if (order < minimumOrder) or (order > maximumOrder) then
		error(`Order ({order}) for Guassian Quadrature must be in the range of [{minimumOrder}, {maximumOrder}]`)
	end

	return LUT[order - minimumOrder]
end