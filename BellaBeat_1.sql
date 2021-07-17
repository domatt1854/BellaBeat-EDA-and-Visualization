---- BREAKING DOWN DATA BY UNIQUE USER ----

--Looking at the mean metrics of each unique user
--As well as the mean percentage of time each user spends in each activity type

DROP TABLE IF EXISTS #averageDailyUserActivities
SELECT
	dailyA.Id,
	AVG(dailyA.Calories) AS AvgDailyCalories,
	AVG(dailyA.TotalDistance) AS AvgTotalDistance,
	AVG(dailyA.VeryActiveMinutes) AS AvgVeryActiveMinutes,
	AVG(dailyA.FairlyActiveMinutes) AS AvgFairlyActiveMinutes,
	AVG(dailyA.LightlyActiveMinutes) AS AvgLightlyActiveMinutes,
	AVG(dailyA.SedentaryMinutes) AS AvgSedentaryMinutes,
	--Casting the minutes to floats as integer division < 1 will always return 0
	100 * (CAST(SUM(SedentaryMinutes) AS float) / CAST(SUM(VeryActiveMinutes + SedentaryMinutes + LightlyActiveMinutes + FairlyActiveMinutes) AS float)) AS percentageSedentary,
	100 * (CAST(SUM(LightlyActiveMinutes) AS float) / CAST(SUM(VeryActiveMinutes + SedentaryMinutes + LightlyActiveMinutes + FairlyActiveMinutes) AS float)) AS percentLightMinutes,
	100 * (CAST(SUM(FairlyActiveMinutes) AS float) / CAST(SUM(VeryActiveMinutes + SedentaryMinutes + LightlyActiveMinutes + FairlyActiveMinutes) AS float)) AS percentModerateMinutes,
	100 * (CAST(SUM(VeryActiveMinutes) AS float) / CAST(SUM(VeryActiveMinutes + SedentaryMinutes + LightlyActiveMinutes + FairlyActiveMinutes) AS float)) AS percentActiveMinutes

--Saving as a Temporary Table to later merge with weight data
INTO #averageDailyUserActivities
FROM BellaBeat..dailyActivity AS dailyA
GROUP BY dailyA.Id
ORDER BY AvgDailyCalories DESC

SELECT * FROM #averageDailyUserActivities


-- Looking at the percent activities by day for each user to see how much their activity type changes by day

SELECT
	Id,
	ActivityDate,
	SedentaryMinutes,
	LightlyActiveMinutes,
	FairlyActiveMinutes,
	VeryActiveMinutes,
	100 * (CAST(SedentaryMinutes AS float) / CAST(VeryActiveMinutes + SedentaryMinutes + LightlyActiveMinutes + FairlyActiveMinutes AS float)) AS percentageSedentary,
	100 * (CAST(LightlyActiveMinutes AS float) / CAST(VeryActiveMinutes + SedentaryMinutes + LightlyActiveMinutes + FairlyActiveMinutes AS float)) AS percentLightMinutes,
	100 * (CAST(FairlyActiveMinutes AS float) / CAST(VeryActiveMinutes + SedentaryMinutes + LightlyActiveMinutes + FairlyActiveMinutes AS float)) AS percentModerateMinutes,
	100 * (CAST(VeryActiveMinutes AS float) / CAST(VeryActiveMinutes + SedentaryMinutes + LightlyActiveMinutes + FairlyActiveMinutes AS float)) AS percentActiveMinutes
FROM BellaBeat..dailyActivity
ORDER BY Id, ActivityDate


--- Comparing Calories, Average Measures, With A User's Weight


-- Getting the Starting and Ending Weight Based on their Weight Log ---
--This query creates a temporary table holding the starting and end dates for each user
DROP TABLE IF EXISTS #minMaxDates
SELECT
	weightLog.Id,
	MAX(weightLog.Date) as maxDate,
	MIN(weightLog.Date) as minDate 
INTO #minMaxDates
FROM BellaBeat..weightLogInfo_merged$ AS weightLog
GROUP BY Id

-- Retrieving the starting weight by joining on the starting dates for each user
DROP TABLE IF EXISTS #minWeight
SELECT
	minMax.*,
	weightLog.WeightPounds AS startingWeight
INTO #minWeight
FROM #minMaxDates as minMax
-- inner join to get only the rows where a user recorded their weight
INNER JOIN BellaBeat..weightLogInfo_merged$ AS weightLog ON minMax.minDate = weightLog.Date AND weightLog.Id = minMax.Id
ORDER BY ID ASC

-- Retrieving the ending weight, merging into the daily averages table to see how activity minutes impacted their weight
-- The rows where there are no changes between the starting and ending date

SELECT
	minMax.Id,
	minMax.maxDate AS EndingDate,
	minWeight.minDate AS StartingDate,
	minWeight.startingWeight,
	weightLog.WeightPounds AS endingWeight,
	avgDaily.AvgTotalDistance,
	avgDaily.AvgSedentaryMinutes,
	avgDaily.AvgVeryActiveMinutes,
	avgDaily.AvgDailyCalories
FROM #minMaxDates AS minMax

--Join to get the ending weight by joining on the final date of each Id
INNER JOIN BellaBeat..weightLogInfo_merged$ AS weightLog ON (minMax.maxDate = weightLog.Date AND minMax.Id = weightLog.Id )
INNER JOIN #minWeight AS minWeight ON (minWeight.Id = minMax.Id)
INNER JOIN #averageDailyUserActivities avgDaily ON avgDaily.Id = minMax.Id
ORDER BY ID ASC


--- Merging together hourly steps, calories, and intensity ---
--- To bring into a Notebook later for more in depth analysis ---
DROP TABLE IF EXISTS #hourlyMetricsMerged
SELECT 
	hourlyCals.Id,
	hourlyCals.ActivityHour,
	hourlyCals.Calories,
	hourlyIntensity.TotalIntensity,
	hourlyIntensity.AverageIntensity,
	hourlySteps.StepTotal
INTO #hourlyMetricsMerged
FROM BellaBeat..hourlyCalories_merged$ AS hourlyCals
--Inner join to get the Hourly Intensities and Hourly Steps
INNER JOIN dbo.hourlyIntensities_merged$ as hourlyIntensity ON hourlyCals.ActivityHour = hourlyIntensity.ActivityHour AND
														       hourlyCals.Id = hourlyIntensity.Id
INNER JOIN dbo.hourlySteps_merged$ as hourlySteps ON hourlyCals.ActivityHour = hourlySteps.ActivityHour AND
														       hourlyCals.Id = hourlySteps.Id
ORDER BY Id, ActivityHour
--Run Below to View Our Newly Created Table
SELECT * FROM #hourlyMetricsMerged


---Creating a View Later for Data Visualization

-- Looking at Total Intensity Vs Calories
-- There certainly exists a correlation between Intensity and Calories Burnt
GO
CREATE VIEW hourlyMetrics AS
SELECT 
	Id,
	ActivityHour,
	Calories,
	AverageIntensity,
	TotalIntensity
FROM #hourlyMetricsMerged
