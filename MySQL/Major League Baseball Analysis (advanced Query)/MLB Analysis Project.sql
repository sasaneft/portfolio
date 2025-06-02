 use maven_advanced_sql;
 
 
-- PART 1:SCHOOL ANALYSIS
select * from players; -- 18589 rows
select * from salaries; -- 24758
select * from school_details; -- 1207
select * from schools;-- 17350 rows


-- -------------------------------------
-- a)In each decade, how many schools were there that produced MLB players? 
-- we need school and decade information and we can get them from the schools table
select ROUND(yearID, -1) as decade, count(distinct schoolID) num_schools
from schools
group by decade
order by decade desc;


-- b) What are the names of the top 5 schools that produced the most players?
select  sd.name_full, count(distinct playerID) as player_count
from schools s
left join school_details sd
on s.schoolID = sd.schoolID
GROUP BY s.schoolID
order by player_count desc
limit 5;

-- c) For each decade, what were the names of the top 3 schools that produced the most players?
-- add s.yearID to the query from the las part and round it to het the decades
-- then use the window function (rank) and then filter the top 3
with ds as (select  round(s.yearID, -1) as decade, sd.name_full, count(distinct playerID) as player_count
			from schools s
			left join school_details sd
			on s.schoolID = sd.schoolID
			GROUP BY decade, s.schoolID
),
row_num as (
			select decade, name_full ,player_count,
			row_number() over(partition by decade order by player_count desc) as row_num
			from ds
)
select * from row_num
where row_num<=3
order by decade desc, row_num ;


-- -------------------------------------------------------------------------------------------------------------------
-- -------------------------------------------------------------------------------------------------------------------


-- PART 2: SALARY ANALYSIS
select * from salaries;


-- a) Return the top 20% of teams in terms of average annual spending
-- i could have done it with much smaller code, but this is more clear

with sal1 as (select yearID, teamID, sum(salary) as year_salary
				from salaries
				group by teamID, yearID),
                
	sp as (select teamID, avg(year_salary) as avg_salary,
		ntile(5) over(order by avg(year_salary) desc) as spend_pct
from sal1
group by teamID
ORDER BY avg_salary desc)

select teamID, ROUND(avg_salary/1000000, 1) as avg_spemd_in_millions-- comma: to add one more decimal point 
from sp
where spend_pct = 1;

-- b) For each team, show the cumulative sum of spending over the years
-- my solution
select yearID, teamID, sum(salary)/1000000 as year_salary,
sum(sum(salary)/1000000) over(partition by teamID order by yearID) as cumul_sum
from salaries
group by teamID, yearID;
                
/* explanation: The alias year_salary is not allowed inside the SUM() window function because SQL evaluates window functions after the SELECT clause.
To address this, the calculation SUM(salary) / 1000000 is repeated directly inside the window function.*/


-- c) Return the first year that each team's cumulative spending surpassed 1 billion

with csp as (
	select yearID, teamID, sum(salary)/1000000 as year_salary,
sum(sum(salary)/1000000) over(partition by teamID order by yearID) as cumul_sum
from salaries
group by teamID, yearID
),

csp2 as (select yearID, teamID, cumul_sum, 
row_number() over(partition by teamID order by yearID) as rrank
from csp
where cumul_sum > 1000)

select yearID as first_over_one_million, teamID, ROUND(cumul_sum/1000,2) as billion
from csp2
where rrank = 1
order by teamID asc;


-- -------------------------------------------------------------------------------------------------------------------
-- -------------------------------------------------------------------------------------------------------------------


-- PART3: Player Career Analysis
select * from players;
select * from schools;
select * from school_details;
-- a) For each player, calculate their age at their first (debut) game, their last game, and their career length (all in years). Sort from longest career to shortest career.
select
	namegiven,
    year(debut)- birthYear as starting_age,
    year(finalGame)- birthYear as ending_age,
    year(finalGame)- year(debut) as career_length
from players
order by career_length desc;
-- alternative approach: use timestampdiff to cast concatenated dates and use that to get the year


-- b) What team did each player play on for their starting and ending years?[joins] IT WAS HARD TO SOLVE
-- 	team information comes from salaries table
SELECT p.playerID, p.nameGiven, p.debut, p.finalGame, s.yearID as starting_year, s.teamID as starting_team, 
e.yearID as final_year, e.teamID as final_team
FROM players p inner join salaries s
	ON p.playerID = s.playerID
    -- we also need to match up debut year and salary:
	AND year(p.debut)=s.yearID -- if we use left join we tend to get many null values(instead inner join)
inner join salaries e
	on p.playerID = e.playerID
	and year(p.finalGame) = e.yearID ;
	


-- c) How many players started and ended on the same team and also played for over a decade?
-- easily using the same query and adding another condition
WITH jj AS (SELECT p.playerID, p.nameGiven, p.debut, p.finalGame, s.yearID AS starting_year, s.teamID AS starting_team, 
e.yearID AS final_year, e.teamID AS final_team
FROM players p INNER JOIN salaries s
	ON p.playerID = s.playerID
    -- we also need to match up debut year and salary:
	AND year(p.debut)=s.yearID -- if we use left join we tend to get many null values(instead inner join)
INNER JOIN salaries e
	ON p.playerID = e.playerID
	AND YEAR(p.finalGame) = e.yearID)
    
select *, final_year - starting_year as years from jj
where starting_team = final_team 
and final_year - starting_year > 10;


-- -------------------------------------------------------------------------------------------------------------------
-- -------------------------------------------------------------------------------------------------------------------


-- PART4: PLAYER COMPARISON ANALYSIS
-- a) Which players have the same birthday?
-- we just need the first 3 cols in the players in the players table and concat-cast to make a date dtype
-- then we can use groupconcat to add these name together

WITH bn as (SELECT CAST(CONCAT(birthYear, "-", birthMonth, "-" ,birthDay)as DATE) as birthdate,
		nameGiven
FROM players
)

-- we cant use where clause in the CTE above
-- instead we use the order clause and where claues along with group claues in the query here:
select birthdate, GROUP_CONCAT(nameGiven SEPARATOR ", ") ,COUNT(nameGiven)
from bn
where birthdate is not null and year(birthdate) between 1980 and 1990
group by birthdate 
having count(nameGiven) >= 2
order by birthdate;

-- b) Create a summary table that shows for each team, what percent of players bat right, left and both.
-- we use salaries as our main table for join
select s.teamID, s.playerID, p.bats,
	case when p.bats="R" then 1 else 0 end as bats_right,
	case when p.bats="L" then 1 else 0 end as bats_left,
    case when p.bats="B" then 1 else 0 end as bats_both
from salaries s left join players p
on s.playerID = p.playerID;

-- next step: we need to group by teams and sum all the KRBs for each team. then divide sums by count of total players in each
-- team to get the percentage
select s.teamID, COUNT(s.playerID) ,
	sum(case when p.bats="R" then 1 else 0 end)/COUNT(s.playerID) as bats_right,
	sum(case when p.bats="L" then 1 else 0 end)/COUNT(s.playerID) as bats_left,
    sum(case when p.bats="B" then 1 else 0 end)/COUNT(s.playerID) as bats_both
from salaries s left join players p
on s.playerID = p.playerID
group by s.teamID;

-- we can also add round function to round the values and get the percent
select s.teamID, COUNT(s.playerID) ,
	round(sum(case when p.bats="R" then 1 else 0 end)/COUNT(s.playerID)*100,1) as pct_bats_right,
	round(sum(case when p.bats="L" then 1 else 0 end)/COUNT(s.playerID)*100,1) as pct_bats_left,
    round(sum(case when p.bats="B" then 1 else 0 end)/COUNT(s.playerID)*100,1) as pct_bats_both
from salaries s left join players p
on s.playerID = p.playerID
group by s.teamID;




-- c) How have average height and weight at debut game changed over the years, and what's the decade-over-decade difference?
-- we round the year with -1 to get the decade
select  ROUND(YEAR(debut), -1) as decade, avg(height) as avg_height, avg(weight) as avg_weight
from players
group by decade
order by decade;

-- to compare decade to decade(every cell to the next cell) we nee d to use window functions
-- so we need tp turn it into CTE first
with cc as (
	select  ROUND(YEAR(debut), -1) as decade, avg(height) as avg_height, avg(weight) as avg_weight
	from players
	group by decade
	order by decade
)

select decade, avg_height, avg_weight,
lag(avg_height) over(order by decade) as height_prior,
lag(avg_weight) over(order by decade) as weight_prior,
avg_height - lag(avg_height) over(order by decade) as height_diff, 
avg_weight- lag(avg_weight) over(order by decade) as weight_diff
from cc;


-- to clean up the query above a bit: just show the necessary cols:
with cc as (
	select  ROUND(YEAR(debut), -1) as decade, avg(height) as avg_height, avg(weight) as avg_weight
	from players
	group by decade
	order by decade
),
difs as (
			select decade, avg_height, avg_weight,
			lag(avg_height) over(order by decade) as height_prior,
			lag(avg_weight) over(order by decade) as weight_prior,
			avg_height - lag(avg_height) over(order by decade) as height_diff, 
			avg_weight- lag(avg_weight) over(order by decade) as weight_diff
			from cc
)

select decade, height_diff, weight_diff from difs
where decade is not null;


select log(12,10);