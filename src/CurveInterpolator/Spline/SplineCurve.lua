-- Root for ease-of-access
local Root = script.Parent.Parent

-- Types
local InternalTypes = require(Root.Core.InternalTypes)

-- Core Modules
local Utils = require(Root.Core.Utils)

-- Define our interface
local Interface = {}

-- Get the four control points for a spline segment
function GetControlPoints(
	segmentIndex: number, points: InternalTypes.Points,
	isClosed: boolean
):(Vector3, Vector3, Vector3, Vector3)
	local pointCount = #points
	if isClosed then
		return
			points[Utils.WrapTableIndex((segmentIndex - 1), pointCount)], -- If 0 wraps back to pointCount
			points[Utils.WrapTableIndex(segmentIndex, pointCount)],
			points[Utils.WrapTableIndex((segmentIndex + 1), pointCount)],
			points[Utils.WrapTableIndex((segmentIndex + 2), pointCount)]
	else
		if segmentIndex == pointCount then
			error(`There is no Spline-Segment at Index ({segmentIndex}) to make a Closed-Curve`)
		end

		local point2, point3 = points[segmentIndex], points[segmentIndex + 1]
		return
			--[[
				Points 1 & 4 extrapolate control-points in the beginning and end segments of an open spline chain
				where ((2 * u) - v) represent Point Bias 1/2
			]]
			(if segmentIndex > 1 then points[segmentIndex - 1] else ((2 * point2) - point3)),
			point2,
			point3,
			(if segmentIndex < (pointCount - 1) then points[segmentIndex + 2] else ((2 * point3) - point2))
	end
end

-- Expose our methods
Interface.GetControlPoints = GetControlPoints

-- Now return our interface (and lock it)
table.freeze(Interface)
return Interface