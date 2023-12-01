-- Root for ease-of-access
local Root = script.Parent.Parent

-- Types
local InternalTypes = require(Root.Core.InternalTypes)

-- Core Modules
local Utils = require(Root.Core.Utils)

-- Spline Modules
local SplineCurve = require(Root.Spline.SplineCurve)
local SplineSegment = require(Root.Spline.SplineSegment)

-- CurveMapper Modules
local BaseCurveMapper = require(Root.CurveMappers.BaseCurveMapper)

-- Our Types
type SegmentedCurveMapperInternal = (
	BaseCurveMapper.BaseCurveMapper
	& {
		SubDivisions: number;
		SegmentArcLengths: InternalTypes.ArcLengths;
		SegmentArcLengthCount: number;
	}
)

--[[ Create our interface

	Approximate spline curve by subdividing it into smaller linear
	line segments. Used to approximate length and mapping between
	'Time' (Non-Linear) and 'Progress' (Linear) on the curve.

]]
local Interface = {
	DefaultSubDivisions = 300;
}

-- Storage Functions
do
	--[[
		Break curve into segments and return the curve length at each segment index.
		Used for mapping between 'Time' and 'Progress' along the curve.
	]]
	function ComputeArcLengths(self: SegmentedCurveMapperInternal)
		-- Make sure we even have points
		local points = self.Points

		-- Now prepare ourselves for length computation
		local lengths: InternalTypes.ArcLengths = {0}
		local last = self:ProcessAxisCoefficientsAtTime(SplineSegment.GetValueAtTime, 0)
		local current: InternalTypes.Point
		local sum = 0
		for subDivision = 1, self.SubDivisions do
			current = self:ProcessAxisCoefficientsAtTime(SplineSegment.GetValueAtTime, (subDivision / self.SubDivisions))
			sum += (current - last).Magnitude
			table.insert(lengths, sum)
			last = current
		end

		self.SegmentArcLengths = lengths
		self.SegmentArcLengthCount = #lengths
	end
end

-- Worker Methods
do
	function GetDistanceFromProgress(
		self: SegmentedCurveMapperInternal,
		progress: number
	): number
		return (Utils.AssertInRange(progress) * self.SegmentArcLengths[self.SegmentArcLengthCount])
	end

	function GetTimeFromProgress(
		self: SegmentedCurveMapperInternal,
		progress: number
	): number
		-- Grab arc-length information
		local arcLengths = self.SegmentArcLengths
		local totalArcLengths = self.SegmentArcLengthCount
		local targetArcLength = (Utils.AssertInRange(progress) * arcLengths[totalArcLengths])

		-- Try to see if we can find our desired arc-length immediately
		local arcIndex = Utils.BinarySearch(targetArcLength, arcLengths)
		if arcLengths[arcIndex] == targetArcLength then
			return Utils.GetIterationProgress(arcIndex, totalArcLengths)
		end

		-- We could get finer grain at lengths, or use simple interpolation between two points
		local lengthBefore = arcLengths[arcIndex]
		local lengthAfter = arcLengths[arcIndex + 1]
		local segmentLength = (lengthAfter - lengthBefore)

		-- Determine where we are between the 'before' and 'after' points
		local segmentFraction = ((targetArcLength - lengthBefore) / segmentLength)

		-- Add that fractional amount to t
		return Utils.GetIterationProgress((arcIndex + segmentFraction), totalArcLengths)
	end

	function GetProgressFromTime(
		self: SegmentedCurveMapperInternal,
		time: number
	): number
		Utils.AssertInRange(time)

		-- Immediate shortcuts (known values)
		if time == 0 then
			return 0
		elseif time == 1 then
			return 1
		end

		-- Grab our arc-length information
		local arcLengths = self.SegmentArcLengths
		local totalArcLengths = self.SegmentArcLengthCount
		local totalLength = arcLengths[totalArcLengths]

		-- Need to denormalize our time to find the matching length
		local denormalizedTimeIndex = Utils.GetIndexFromScale(time, totalArcLengths, true)
		local subDenormalizedTimeIndex = math.floor(denormalizedTimeIndex)
		local subDenormalizedTimeLength = arcLengths[subDenormalizedTimeIndex]
		if denormalizedTimeIndex == subDenormalizedTimeIndex then
			return (subDenormalizedTimeLength / totalLength)
		end

		-- Measure the length between our provided progress and the progress at SubDenormalizedProgressIndex
		local subTime = Utils.GetIterationProgress(subDenormalizedTimeIndex, totalArcLengths)
		local subPoint = self:ProcessAxisCoefficientsAtTime(SplineSegment.GetValueAtTime, subTime)
		local ourPoint = self:ProcessAxisCoefficientsAtTime(SplineSegment.GetValueAtTime, time)
		local length = (subDenormalizedTimeLength + (ourPoint - subPoint).Magnitude)

		return (length / totalLength)
	end
end

-- State Management Functions
function OnCacheUpdate(self: SegmentedCurveMapperInternal)
	ComputeArcLengths(self)
end

-- Contructor
function Interface.new(
	subDivisions: number,
	configuration: BaseCurveMapper.Configuration
): BaseCurveMapper.ImplementedCurveMapper
	return BaseCurveMapper.Implement(
		configuration,
		{
			SubDivisions = subDivisions;
		},
		OnCacheUpdate,
		GetDistanceFromProgress,
		GetTimeFromProgress,
		GetProgressFromTime
	)
end

-- Freeze and then return our interface
table.freeze(Interface)
return Interface