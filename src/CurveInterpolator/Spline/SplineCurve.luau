-- Root for ease-of-access
local Root = script.Parent.Parent

-- Types
local InternalTypes = require(Root.Core.InternalTypes)

-- Core Modules
local Utils = require(Root.Core.Utils)

-- Define our interface
local Interface = {}

--[[
	Used to extrapolate points in the beginning and end segments of an open spline chain
	where (u, v) represent Point Bias 1/2.
]]
local function ExtrapolateControlPoint(u: InternalTypes.Point, v: InternalTypes.Point): InternalTypes.Point
	return ((2 * u) - v) -- We use any type-casting here because Luau doesn't know how to process this yet
end

-- Get the four control points for a spline segment
local function GetControlPoints(
	segmentIndex: number, points: InternalTypes.Points,
	isClosed: boolean
): InternalTypes.Points
	local pointCount = #points
	if isClosed then
		return {
			points[Utils.WrapTableIndex((segmentIndex - 1), pointCount)], -- If 0 wraps back to pointCount
			points[Utils.WrapTableIndex(segmentIndex, pointCount)],
			points[Utils.WrapTableIndex((segmentIndex + 1), pointCount)],
			points[Utils.WrapTableIndex((segmentIndex + 2), pointCount)]
		}
	else
		if segmentIndex == pointCount then
			error(`There is no Spline-Segment at Index ({segmentIndex}) to make a Closed-Curve`)
		end

		local point2, point3 = points[segmentIndex], points[segmentIndex + 1]
		return {
			(if segmentIndex > 1 then points[segmentIndex - 1] else ExtrapolateControlPoint(point2, point3)),
			point2,
			point3,
			(if segmentIndex < (pointCount - 1) then points[segmentIndex + 2] else ExtrapolateControlPoint(point3, point2))
		}
	end
end

--[[
	Find the spline segment index and the corresponding segment weight/fraction
	at the provided non-linear progress on the curve
]]
type SegmentDetails = {
	Index: number;
	Weight: number;
}
local function GetSegmentDetailsAtTime(
	time: number, points: InternalTypes.Points,
	isClosed: boolean
): SegmentDetails
	local maximumPointIndex = (isClosed and (#points + 1) or #points)

	-- If we're at the end we can shortcut our return
	if time == 1 then
		return {
			Index = (maximumPointIndex - 1);
			Weight = 1;
		}
	end

	local rawPointCountIndex = Utils.GetIndexFromScale(time, maximumPointIndex, true)
	local index = math.floor(rawPointCountIndex)
	local weight = (rawPointCountIndex - index)
	return {
		Index = index;
		Weight = weight;
	}
end

-- Expose our methods
Interface.ExtrapolateControlPoint = ExtrapolateControlPoint
Interface.GetControlPoints = GetControlPoints
Interface.GetSegmentDetailsAtTime = GetSegmentDetailsAtTime

-- Now return our interface (and lock it)
table.freeze(Interface)
return Interface