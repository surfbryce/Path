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

-- Our Modules
local FindGauss = require(script.Gauss)

-- Our Types
type Samples = {FindGauss.Gauss}
type NumericalCurveMapperInternal = (
	BaseCurveMapper.BaseCurveMapper
	& {
		Gauss: FindGauss.Gauss;
		SampleCount: number;

		CachedSamples: Samples;
		CachedArcLengths: InternalTypes.ArcLengths?;
	}
)

--[[ Create our interface

	This curve mapper implementation uses a numerical integration method (Gauss Legendre)
	in order to approximate curve segment lengths. For re-parameterization of the curve
	function in terms of arc length, a number of precalculated lengths (samples) is used
	to fit a monotone piecewise cubic function using the approach suggested here:
	https://stackoverflow.com/questions/35275073/uniform-discretization-of-bezier-curve

]]
local Interface = {
	DefaultQuadraturePointCount = 24;
	DefaultInverseSamples = 21;
}

-- Worker Functions
do
	-- Computes the arc length of a curve segment
	function ComputeArcLength(
		numericalCurveMapper: NumericalCurveMapperInternal,
		segmentIndex: number, startTime: number?, endTime: number?
	)
		local startTime, endTime = (startTime or 0), (endTime or 1)
		if startTime == endTime then
			return 0
		end

		local coefficients = numericalCurveMapper:CalculateCoefficientsPerAxisForSegment(segmentIndex)
		local z = ((endTime - startTime) * 0.5)
		local sum = 0
		for index = 1, #numericalCurveMapper.Gauss do
			local gauss = numericalCurveMapper.Gauss[index]
			local segmentTime = (startTime + (z * gauss[1]) + z)
			local deltaLength = SplineSegment.ProcessAxisCoefficientsAtSegmentTime(
				SplineSegment.GetDerivativeAtTime, segmentTime,
				coefficients
			).Magnitude
			sum += (gauss[2] * deltaLength)
		end

		return (z * sum)
	end

	--[[
		Break curve into segments and return the curve length at each segment index.
		Used for mapping between 'Time' and 'Progress' along the curve.
	]]
	function ComputeArcLengths(
		numericalCurveMapper: NumericalCurveMapperInternal
	): InternalTypes.ArcLengths
		-- Make sure we even have points
		local points = numericalCurveMapper.Points

		-- Now prepare ourselves for length computation
		local lengths: InternalTypes.ArcLengths = {0}
		local pointCount = (numericalCurveMapper.Closed and #points or (#points - 1))
		local sum = 0
		for index = 1, pointCount do
			local length = ComputeArcLength(numericalCurveMapper, index)
			sum += length
			table.insert(lengths, sum)
		end

		return lengths
	end

	--[[
		Get samples for inverse function from cache if present, otherwise calculate and put
		in cache for re-use.

		Returns lengths, slopes, and 2nd/3rd coefficients for inverse function.
	]]
	function GetSamples(
		numericalCurveMapper: NumericalCurveMapperInternal,
		segmentIndex: number
	): Samples
		-- Make sure we even have points
		local points = numericalCurveMapper.Points

		-- Check if our samples exist (or if we have to create them)
		local samples = numericalCurveMapper.CachedSamples[segmentIndex]
		if samples == nil then
			-- Calculate our lengths/slopes
			local sampleCount = numericalCurveMapper.SampleCount
			local lengths: {number}, slopes: {number} = {}, {}
			local coefficients = numericalCurveMapper:CalculateCoefficientsPerAxisForSegment(segmentIndex)
			for index = 1, sampleCount do
				local sampleTime = Utils.GetIterationProgress(index, sampleCount)
				local deltaLength = SplineSegment.ProcessAxisCoefficientsAtSegmentTime(
					SplineSegment.GetDerivativeAtTime, sampleTime,
					coefficients
				).Magnitude
				local slope = ((deltaLength == 0) and 0 or (1 / deltaLength))

				-- Avoid extreme slopes for near linear curves at the segment endpoints (low curviness parameter value)
				if numericalCurveMapper.Curviness < 0.05 then
					slope = math.clamp(slope, -1, 1)
				end

				table.insert(slopes, slope)
				table.insert(lengths, ComputeArcLength(numericalCurveMapper, segmentIndex, 0, sampleTime))
			end

			-- Precalculate the cubic interpolant coefficients
			local coefficientCount = (sampleCount - 1)
			local degree3Coefficients, degree2Coefficients = {}, {}
			local previousLength = lengths[1]
			local previousSlope = slopes[1]
			local step = (1 / coefficientCount)
			for index = 1, coefficientCount do
				-- Store our length and then move up for the next iteration
				local length = previousLength
				previousLength = lengths[index + 1]

				-- Store length information
				local lengthDifference = (previousLength - length)

				-- Store our sloep and then move it up for the next iteration
				local slope = previousSlope
				local nextSlope = slopes[index + 1]
				previousSlope = nextSlope

				-- Calculate our coefficient steepness and our coefficients
				local steepness = (step / lengthDifference)
				local degree3 = ((slope + nextSlope - (2 * steepness)) / (lengthDifference ^ 2))
				local degree2 = (((3 * steepness) - (2 * slope) - nextSlope) / lengthDifference)
				table.insert(degree3Coefficients, degree3)
				table.insert(degree2Coefficients, degree2)
			end

			-- Now store our sample
			samples = {lengths, slopes, degree2Coefficients, degree3Coefficients}
			numericalCurveMapper.CachedSamples[segmentIndex] = samples
		end

		return samples
	end

	-- Calculate Time from arc length for a curve segment
	function GetTimeFromArcLength(
		numericalCurveMapper: NumericalCurveMapperInternal,
		segmentIndex: number, length: number
	): number
		-- Extract our samples
		local samples = GetSamples(numericalCurveMapper, segmentIndex)
		local lengths, slopes = samples[1], samples[2]
		local degree2Coefficients, degree3Coefficients = samples[3], samples[4]
		local maximumLength = lengths[#lengths]

		-- Handle shortcuts
		if length >= maximumLength then
			return 1
		elseif length <= 0 then
			return 0
		end

		-- Find the cubic-segment which has our length
		local coefficientCount = (numericalCurveMapper.SampleCount - 1)
		local step = (1 / coefficientCount)
		local index = Utils.BinarySearch(length, lengths)
		local indexTime = ((index - 1) * step)
		if lengths[index] == length then
			return indexTime
		end

		-- Otherwise, calculate the remaining progress from our provided segment
		local slope, degree3, degree2 = slopes[index], degree3Coefficients[index], degree2Coefficients[index]
		local lengthDelta = (length - lengths[index])

		return (indexTime + (((((degree3 * lengthDelta) + degree2) * lengthDelta) + slope) * lengthDelta))
	end
end

-- Worker Methods
do
	function GetArcLengths(numericalCurveMapper: NumericalCurveMapperInternal): InternalTypes.ArcLengths
		local arcLengths = numericalCurveMapper.CachedArcLengths
		if arcLengths == nil then
			arcLengths = ComputeArcLengths(numericalCurveMapper)
			numericalCurveMapper.CachedArcLengths = arcLengths
		end

		return arcLengths
	end

	function GetDistanceFromProgress(
		numericalCurveMapper: NumericalCurveMapperInternal,
		progress: number
	): number
		local arcLengths = GetArcLengths(numericalCurveMapper)
		return (Utils.AssertInRange(progress) * arcLengths[#arcLengths])
	end

	function GetTimeFromProgress(
		numericalCurveMapper: NumericalCurveMapperInternal,
		progress: number
	): number
		-- Grab arc-length information
		local arcLengths = GetArcLengths(numericalCurveMapper)
		local totalArcLengths = #arcLengths
		local targetArcLength = (Utils.AssertInRange(progress) * arcLengths[totalArcLengths])

		-- Try to see if we can find our desired arc-length immediately
		local arcIndex = Utils.BinarySearch(targetArcLength, arcLengths)
		if arcLengths[arcIndex] == targetArcLength then
			return Utils.GetIterationProgress(arcIndex, totalArcLengths)
		end

		-- Otherwise, return the progress based off our remaining length
		local remainingLength = (targetArcLength - arcLengths[arcIndex])
		local fraction = GetTimeFromArcLength(numericalCurveMapper, arcIndex, remainingLength)
		return Utils.GetIterationProgress((arcIndex + fraction), totalArcLengths)
	end

	function GetProgressFromTime(
		numericalCurveMapper: NumericalCurveMapperInternal,
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
		local arcLengths = GetArcLengths(numericalCurveMapper)
		local totalArcLengths = #arcLengths
		local totalLength = arcLengths[totalArcLengths]

		-- Need to denormalize our progress to find the matching length
		local denormalizedTimeIndex = Utils.GetIndexFromScale(time, totalArcLengths, true)
		local subDenormalizedTimeIndex = math.floor(denormalizedTimeIndex)
		local subDenormalizedTimeLength = arcLengths[subDenormalizedTimeIndex]
		if denormalizedTimeIndex == subDenormalizedTimeIndex then
			return (subDenormalizedTimeLength / totalLength)
		end

		-- Find the remaining distance
		local deltaIndex = (denormalizedTimeIndex - subDenormalizedTimeIndex)
		local fraction = ComputeArcLength(numericalCurveMapper, subDenormalizedTimeIndex, 0, deltaIndex)
		return ((subDenormalizedTimeLength + fraction) / totalLength)
	end
end

-- State Management Methods
function InvalidateCache(numericalCurveMapper: NumericalCurveMapperInternal)
	numericalCurveMapper.CachedArcLengths = nil
	numericalCurveMapper.CachedSamples = {}
	numericalCurveMapper:InvalidateBaseCache()
end

-- Constructor
function Interface.new(
	quadraturePointCount: number, inverseSamples: number,
	configuration: BaseCurveMapper.Configuration
): BaseCurveMapper.ImplementedCurveMapper
	return BaseCurveMapper.Implement(
		configuration,
		{
			Gauss = FindGauss(quadraturePointCount);
			SampleCount = inverseSamples;

			CachedSamples = {};
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