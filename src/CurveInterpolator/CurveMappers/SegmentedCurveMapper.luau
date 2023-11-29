-- Root for ease-of-access
local Root = script.Parent.Parent

-- Types
local InternalTypes = require(Root.Core.InternalTypes)

-- Core Modules
local Math = require(Root.Core.Math)
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
		CachedArcLengths: InternalTypes.ArcLengths?;
	}
)

--[[ Create our interface

	Approximate spline curve by subdividing it into smaller linear
	line segments. Used to approximate length and mapping between
	'Time' (Linear) and 'Progress' (Non-Linear) on the curve.

]]
local Interface = {
	DefaultSubDivisions = 300;
}

-- Worker Functions
do
	--[[
		Break curve into segments and return the curve length at each segment index.
		Used for mapping between 'Time' and 'Progress' along the curve.
	]]
	function ComputeArcLengths(segmentedCurveMapper: SegmentedCurveMapperInternal): InternalTypes.ArcLengths
		local lengths: InternalTypes.ArcLengths = {0}
		local last = segmentedCurveMapper:ProcessAxisCoefficientsAtTime(SplineSegment.GetValueAtTime, 0)
		local current: InternalTypes.Point
		local sum = 0
		for subDivision = 1, segmentedCurveMapper.SubDivisions do
			current = segmentedCurveMapper:ProcessAxisCoefficientsAtTime(
				SplineSegment.GetValueAtTime, (subDivision / segmentedCurveMapper.SubDivisions)
			)
			sum += (current - last).Magnitude
			table.insert(lengths, sum)
			last = current
		end

		return lengths
	end
end

-- Worker Methods
do
	function GetArcLengths(segmentedCurveMapper: SegmentedCurveMapperInternal): InternalTypes.ArcLengths
		local arcLengths = segmentedCurveMapper.CachedArcLengths
		if arcLengths == nil then
			arcLengths = ComputeArcLengths(segmentedCurveMapper)
			segmentedCurveMapper.CachedArcLengths = arcLengths
		end

		return arcLengths
	end

	function GetDistanceFromProgress(
		segmentedCurveMapper: SegmentedCurveMapperInternal,
		progress: number
	): number
		local arcLengths = GetArcLengths(segmentedCurveMapper)
		return (Utils.AssertInRange(progress) * arcLengths[#arcLengths])
	end

	function GetTimeFromProgress(
		segmentedCurveMapper: SegmentedCurveMapperInternal,
		progress: number
	): number
		-- Grab arc-length information
		local arcLengths = GetArcLengths(segmentedCurveMapper)
		local totalArcLengths = #arcLengths
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
		segmentedCurveMapper: SegmentedCurveMapperInternal,
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
		local arcLengths = GetArcLengths(segmentedCurveMapper)
		local totalArcLengths = #arcLengths
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
		local subPoint = segmentedCurveMapper:ProcessAxisCoefficientsAtTime(
			SplineSegment.GetValueAtTime, subTime
		)
		local ourPoint = segmentedCurveMapper:ProcessAxisCoefficientsAtTime(
			SplineSegment.GetValueAtTime, time
		)
		local length = (subDenormalizedTimeLength + (ourPoint - subPoint).Magnitude)

		return (length / totalLength)
	end
end

-- State Management Methods
function InvalidateCache(segmentedCurveMapper: SegmentedCurveMapperInternal)
	segmentedCurveMapper.CachedArcLengths = nil
	segmentedCurveMapper:InvalidateBaseCache()
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
			CachedArcLengths = nil;
		},
		InvalidateCache,
		GetDistanceFromProgress,
		GetTimeFromProgress,
		GetProgressFromTime
	)
end

-- Freeze and then return our interface
table.freeze(Interface)
return Interface