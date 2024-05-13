/* 
PostgreSQL
 
Data source:
Web-site for mentoring
Mentor and mentee may schedule online meeting at personal accounts after login

Skills:
Queries, subqueries, CTE, window functions, aggregation, converting data types
запросы, подзапросы, CTE, оконные функции, агрегирование, изменение типов данных
*/

--------------------------------------------------------------------------------------------------------------------------
-- 01 Web-site usage: number of meetings by months and month to  month dynamic

select
	*,
	case 
		when t2.n_session_growth = 0 
			OR t2.n_session_growth = NULL  then 0
		else round(t2.n_sessions / (t2.n_sessions - t2.n_session_growth) , 2) - 1
	end as pct_session_growth
from (-- Amount of sessions by year and month, change to previous month
		select 
			*,
			round(n_sessions - lag(n_sessions) over(order by t1.session_yy_mm), 2) as n_session_growth 
		from (-- Amount of sessions by year and month
				select 
					to_char(s.session_date_time, 'YY-MM') as session_yy_mm,
					count(*) as n_sessions
				from sessions s
				group by to_char(s.session_date_time, 'YY-MM')
			) t1
	) t2

--------------------------------------------------------------------------------------------------------------------------
-- 02 How many mentors and mentee haven't been in a single session?

select 
	('mentee') as user_role,
	count(*) as n_users
from (-- ID mentee from users list with 0 sessions
		select 
			user_id
		from users u 
		where u.role = 'mentee'
		except 
		select 
			distinct (s.mentee_id)
		from sessions s 
	) t
union all
select
	('mentor') as user_role,
	count(*) as n_users
from (-- ID mentros from users list with 0 sessions 
		select 
			user_id
		from users u 
		where u.role = 'mentor'
		except 
		select 
			distinct (s.mentor_id)
		from sessions s 
	) t

/* All mentors have been at least at 1 session, but 662 mentee with 0 sessions to date
Hypothesis: there are no free or convenient (domain, region, time zone) mentors
--> to check: 
--> mentors load
--> amount of mentors by domain
--> cancelled sessions by domain
*/
	
--------------------------------------------------------------------------------------------------------------------------	
-- 03 Mentors load by months
-- 03.1 Average number of sessions for a mentor by weeks in month

select 
	t1.mentor_id,
	t1.yy_mm,
	sum(t1.n_sessions) / (4 * 1.0) as avg_sessions
from (-- number of sessions by mentor, month, week
			select 
				to_char(s.session_date_time, 'YY-MM') as yy_mm,
				s.mentor_id, 
				to_char(s.session_date_time, 'w') as wk,
				count(*) as n_sessions
			from sessions s 
			where s.session_status = 'finished'
			group by 
				s.mentor_id, 
				to_char(s.session_date_time, 'YY-MM'),
				to_char(s.session_date_time, 'w')
	) t1
group by t1.mentor_id, t1.yy_mm
order by t1.mentor_id, t1.yy_mm

-- 03.2 Changes in sessions numbers from month to month

select 
	t1.mentor_id,
	t1.yy_mm,
	sum(t1.n_sessions) / (4 * 1.0) as avg_sessions
from ( -- number of sessions by mentor, month and week
		select 
			to_char(s.session_date_time, 'YY-MM') as yy_mm,
			s.mentor_id, 
			to_char(s.session_date_time, 'w') as wk,
			count(*) as n_sessions
		from sessions s 
		where s.session_status = 'finished'
		group by 
			s.mentor_id, 
			to_char(s.session_date_time, 'YY-MM'), 
			to_char(s.session_date_time, 'w')
		order by 
			s.mentor_id, 
			to_char(s.session_date_time, 'YY-MM')
	) t1 
group by t1.mentor_id, t1.yy_mm
order by t1.yy_mm, t1.mentor_id

-- 03.3 Top-5 mentors by number of sessions for the last full month 

select 
	s.mentor_id,
	count(*)
from sessions s
where 
	to_char(s.session_date_time, 'YY-MM-DD') > '22-07-31'
	and to_char(s.session_date_time, 'YY-MM-DD') < '22-09-01'
group by s.mentor_id
order by  count(*) desc
limit 5

--------------------------------------------------------------------------------------------------------------------------
-- 04. "Free" time of mentors and mentee
-- 04.1 Average time interval between sessions for every mentee? 

select 
	t2.mentor_id,
	avg(t2.time_delta)
from (-- difference between sessions by mentee
		select 
			t1.mentor_id,
			age(t1.session_date_time, lg_date) as time_delta
		from (-- mentee, date and previous date
				select 
					s.mentor_id ,
					lag(s.session_date_time) over(partition by s.mentor_id order by s.session_date_time) as lg_date,
					s.session_date_time
				from sessions s
				order by s.mentor_id
			) t1
		) t2
group by t2.mentor_id
	
-- 04.2 By mentor?

select 
	t2.mentee_id,
	avg(t2.time_delta)
from (-- 
		select 
			t1.mentee_id,
			age(t1.session_date_time, lg_date) as time_delta
		from (-- mentee, date and previous date
				select 
					s.mentee_id ,
					lag(s.session_date_time) over(partition by s.mentee_id order by s.session_date_time) as lg_date,
					s.session_date_time
				from sessions s
				order by s.mentee_id
			) t1
		)t2
group by t2.mentee_id

--------------------------------------------------------------------------------------------------------------------------
-- 05 Session cancelling problem 
-- 05.1 How many sessions for domain cancelled by month? 

with canceled_sessions_by_domain as (
	select 
		d.name,
		t1.yy_mm,
		t1.n_sessions_canceled
	from (-- Number of cancelled sessions for every domain by month
			select 
				to_char(s.session_date_time, 'YY-MM') as yy_mm,
				s.mentor_domain_id,
				count(*) as n_sessions_canceled
			from sessions s
			where s.session_status = 'canceled'
			group by 
				to_char(s.session_date_time, 'YY-MM'), 
				s.mentor_domain_id 
		) t1
	left join domain d
	on t1.mentor_domain_id = d.id
	order by 
		d.name, 
		t1.yy_mm
	)
select 
	csbd.name,
	round(avg(csbd.n_sessions_canceled), 2) as sessions_canceled_avg
from canceled_sessions_by_domain csbd
group by csbd.name

-- 05.2 How fraction ofcancelled sessions changed by month?

select 
	*,
	coalesce (round(t1.n_canceled / (t1.n_sessions * 1.0), 3), 0) as canceled_ratio
from (
	with sessions_canceled as (-- Number of cancelled sessions by year and month
		select 
			to_char(s.session_date_time, 'YY-MM') as yy_mm,
			count(*) as n_canceled
		from sessions s 
		where s.session_status = 'canceled'
		group by to_char(s.session_date_time, 'YY-MM')
		order by to_char(s.session_date_time, 'YY-MM')
		), 
	sessions_all as(-- Number of sessions by year and month
		select 
			to_char(s.session_date_time, 'YY-MM') as yy_mm,
			count(*) as n_sessions
		from sessions s 
		group by to_char(s.session_date_time, 'YY-MM')
		order by to_char(s.session_date_time, 'YY-MM')
		) 
	select
		sa.yy_mm,
		sc.n_canceled,
		sa.n_sessions
	from sessions_all sa	
	left join sessions_canceled sc
	on sa.yy_mm = sc.yy_mm
	) t1

--------------------------------------------------------------------------------------------------------------------------
-- 06.1 Day of week from last full month with biggest number of sessions 

select 
	to_char(s.session_date_time, 'day') as weekday,
	count(*) as n_sessions
from sessions s 
where 
	to_char(s.session_date_time, 'YY-MM-DD') > '22-07-31'
	and to_char(s.session_date_time, 'YY-MM-DD') < '22-09-01'
group by to_char(s.session_date_time, 'day')
order by count(*) desc
	
-- 06.2 Day of week for every domain with highest number of sessions 

with domain_rush_days as (-- domain id, weekday with highest load, number of sessions
	select 
		mentor_domain_id,
		weekday,
		n_sessions
	from (select -- adding row number with window function 
		*,
		row_number() over(partition by mentor_domain_id) as rn
			from (-- number of finished sessions by a weekday and domain
					select 
						s.mentor_domain_id,
						to_char(s.session_date_time, 'day') as weekday,
						count(*) as n_sessions
					from sessions s
					where s.session_status = 'finished'
					group by s.mentor_domain_id, to_char(s.session_date_time, 'day')
					order by s.mentor_domain_id, count(*) desc
					) t1 
		)t2
	where rn = 1
	)
select 
	d.name,
	drd.weekday,
	drd.n_sessions
from domain d
left join domain_rush_days drd
on d.id = drd.mentor_domain_id

--------------------------------------------------------------------------------------------------------------------------
-- 07. Additional analysis
-- 07.1 Top-10 regions by number of users

with users_stat as (
	select
		region_id,
		n_users, 
		round(n_users / sum(n_users) over(), 3) as pct_users
	from (
			select 
				region_id,
				count(*) as n_users
			from users u
			group by region_id
		) t
	)
select 
	r.name,
	us.n_users,
	us.pct_users
from region r 
join users_stat us
on r.id  = us.region_id
order by us.n_users desc
limit 10

-- 07.2 Number of mentors by domain
/* current query will work because every mentor has been at least on 1 session, 
but if there would be a mentor with 0 sessions - base would not allow to get the mentor in the result*/

with mentors_per_domain as (
			select 
				s.mentor_domain_id,
				count(distinct(s.mentor_id)) as n_mentors
			from sessions s
			group by s.mentor_domain_id
)
select 
	d.name, 
	mpd.n_mentors
from domain d
left join mentors_per_domain mpd
on d.id = mpd.mentor_domain_id
order by n_mentors desc

-- 07.3 How many sessions scheduled by domain?
-- Number of sessions for mentee by number of domains

select 
	n_domains,
	count(*) as n_sessions
from (
		select 
			s.mentee_id,
			count(distinct(s.mentor_domain_id)) as n_domains
		from sessions s 
		group by s.mentee_id 
		) t
group by n_domains
order by n_domains desc

-- Will there be changes for cancelled sessions?

select 
	n_domains,
	count(*) as n_sessions
from (
		select 
			s.mentee_id,
			count(distinct(s.mentor_domain_id)) as n_domains
		from sessions s 
		where s.session_status = 'canceled'
		group by s.mentee_id 
		) t
group by n_domains
order by n_domains desc

/* Highest number of cancelled sessions for mentee with sessions by single domain*/

-- Number of cancelled sessions by domain

with canceled_sessions_by_domain as (
		select 
			s.mentor_domain_id,
			count(*) as n_sessions_canceled
		from sessions s 
		where s.session_status = 'canceled'
		group by s.mentor_domain_id
		)
select
	d.name,
	csbd.n_sessions_canceled
from domain d
left join canceled_sessions_by_domain csbd
on d.id = csbd.mentor_domain_id
order by csbd.n_sessions_canceled desc

/* Range for cancelled sessions by domain is between 126 and 189 */