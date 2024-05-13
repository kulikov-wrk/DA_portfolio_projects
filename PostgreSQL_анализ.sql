/* 
PostgreSQL
 
Источник:
Платформа онлайн встреч для менторства. 
Встречи проходят на площадке сервиса. 
Назначить встречу можно в личном кабинете после авторизации на сайте. 

Навыки:
запросы, подзапросы, CTE, оконные функции, агрегирование, изменение типов данных
*/

--------------------------------------------------------------------------------------------------------------------------
-- 01 Использование платформы: количество запланированных встреч по месяцам + динамика месяц к месяцу

select
	*,
	case 
		when t2.n_session_growth = 0 
			OR t2.n_session_growth = NULL  then 0
		else round(t2.n_sessions / (t2.n_sessions - t2.n_session_growth) , 2) - 1
	end as pct_session_growth
from (-- Количество сессий по году-месяцу, изменение к прошлому месяцу
		select 
			*,
			round(n_sessions - lag(n_sessions) over(order by t1.session_yy_mm), 2) as n_session_growth 
		from (-- Количество сессий по году-месяцу
				select 
					to_char(s.session_date_time, 'YY-MM') as session_yy_mm,
					count(*) as n_sessions
				from 
					sessions s
				group by 
					to_char(s.session_date_time, 'YY-MM')
			) t1
	) t2

--------------------------------------------------------------------------------------------------------------------------
-- 02 Сколько менторов и менти еще не приняли участие ни в 1 встрече?

select 
	('mentee') as user_role,
	count(*) as n_users
from (-- ID менти из списка пользователей, не встречающиеся в сессиях
		select 
			user_id
		from 
			users u 
		where 
			u.role = 'mentee'
		except 
		select 
			distinct (s.mentee_id)
		from 
			sessions s 
	) t
union all
select
	('mentor') as user_role,
	count(*) as n_users
from (-- ID менторов из списка пользователей, не встречающиеся в сессиях
		select 
			user_id
		from 
			users u 
		where 
			u.role = 'mentor'
		except 
		select 
			distinct (s.mentor_id)
		from 
			sessions s 
	) t

/* Все менторы участвовали хотя бы в 1 сессии, но 662 менти ни разу не назначили встреч (даже отмененных)
Гипотеза: нет подходящих (направление, регион, часовой пояс?) или свободных менторов
--> проверка: 
--> загруженности менторов
--> количества менторов по направлениям
--> проверка отмены сессий по пользователям и направлениям менторства
*/
	
--------------------------------------------------------------------------------------------------------------------------	
-- 03 Загрузка менторов по месяцам
-- 03.1 Среднее количество проведенных сессий по неделям в месяц у каждого ментора

select 
	t1.mentor_id,
	t1.yy_mm,
	sum(t1.n_sessions) / (4 * 1.0) as avg_sessions
from (-- количество сессий по ментору, месяцам и неделям
			select 
				to_char(s.session_date_time, 'YY-MM') as yy_mm,
				s.mentor_id, 
				to_char(s.session_date_time, 'w') as wk,
				count(*) as n_sessions
			from sessions s 
			where 
				s.session_status = 'finished'
			group by 
				s.mentor_id, 
				to_char(s.session_date_time, 'YY-MM'),
				to_char(s.session_date_time, 'w')
	) t1
group by 
	t1.mentor_id, 
	t1.yy_mm
order by 
	t1.mentor_id, 
	t1.yy_mm

-- 03.2 Изменения частоты проведенных сессий от месяца к месяцу

select 
	t1.mentor_id,
	t1.yy_mm,
	sum(t1.n_sessions) / (4 * 1.0) as avg_sessions
from ( -- количество сессий по ментору, месяцам и неделям
		select 
			to_char(s.session_date_time, 'YY-MM') as yy_mm,
			s.mentor_id, 
			to_char(s.session_date_time, 'w') as wk,
			count(*) as n_sessions
		from 
			sessions s 
		where 
			s.session_status = 'finished'
		group by 
			s.mentor_id, 
			to_char(s.session_date_time, 'YY-MM'), 
			to_char(s.session_date_time, 'w')
		order by 
			s.mentor_id, 
			to_char(s.session_date_time, 'YY-MM')
	) t1 
group by 
	t1.mentor_id, 
	t1.yy_mm
order by 
	t1.yy_mm, 
	t1.mentor_id

-- 03.3 Топ-5 менторов по количеству сессий за последний полный месяц

select 
	s.mentor_id,
	count(*)
from 
	sessions s
where 
	to_char(s.session_date_time, 'YY-MM-DD') > '22-07-31'
	and to_char(s.session_date_time, 'YY-MM-DD') < '22-09-01'
group by 
	s.mentor_id
order by  
	count(*) desc
limit 5

--------------------------------------------------------------------------------------------------------------------------
-- 04. "Свободное" время менторов и менти
-- 04.1 Сколько времени в среднем проходит между менторскими встречами у одного менти? 

select 
	t2.mentor_id,
	avg(t2.time_delta)
from (-- разница между сессиями по менторам
		select 
			t1.mentor_id,
			age(t1.session_date_time, lg_date) as time_delta
		from (-- ментии, дата и предыдущая дата
				select 
					s.mentor_id ,
					lag(s.session_date_time) over(partition by s.mentor_id order by s.session_date_time) as lg_date,
					s.session_date_time
				from 
					sessions s
				order by 
					s.mentor_id
			) t1
		) t2
group by 
	t2.mentor_id
	
-- 04.2 Ментора?

select 
	t2.mentee_id,
	avg(t2.time_delta)
from (-- разница между 
		select 
			t1.mentee_id,
			age(t1.session_date_time, lg_date) as time_delta
		from (-- ментии, дата и предыдущая дата
				select 
					s.mentee_id ,
					lag(s.session_date_time) over(partition by s.mentee_id order by s.session_date_time) as lg_date,
					s.session_date_time
				from 
					sessions s
				order by 
					s.mentee_id
			) t1
		)t2
group by t2.mentee_id

--------------------------------------------------------------------------------------------------------------------------
-- 05 Проблемы отмены сессий 
-- 05.1 Сколько сессий по каждому направлению менторства в месяц обычно отменяется? 

with canceled_sessions_by_domain as (
	select 
		d.name,
		t1.yy_mm,
		t1.n_sessions_canceled
	from (-- количество отмененных сессий по направлению менторства по каждому месяцу
			select 
				to_char(s.session_date_time, 'YY-MM') as yy_mm,
				s.mentor_domain_id,
				count(*) as n_sessions_canceled
			from 
				sessions s
			where 
				s.session_status = 'canceled'
			group by 
				to_char(s.session_date_time, 'YY-MM'), 
				s.mentor_domain_id 
		) t1
	left join domain d
	on 
		t1.mentor_domain_id = d.id
	order by 
		d.name, 
		t1.yy_mm
	)
select 
	csbd.name,
	round(avg(csbd.n_sessions_canceled), 2) as sessions_canceled_avg
from 
	canceled_sessions_by_domain csbd
group by 
	csbd.name

-- 05.2 Как меняется доля отмененных сессий помесячно?

select 
	*,
	coalesce (round(t1.n_canceled / (t1.n_sessions * 1.0), 3), 0) as canceled_ratio
from (
	with sessions_canceled as (-- Количество отмененных сессий по году-месяцу
		select 
			to_char(s.session_date_time, 'YY-MM') as yy_mm,
			count(*) as n_canceled
		from 
			sessions s 
		where 
			s.session_status = 'canceled'
		group by 
			to_char(s.session_date_time, 'YY-MM')
		order by 
			to_char(s.session_date_time, 'YY-MM')
		), 
	sessions_all as(-- Количество сессий всего по году-месяцу
		select 
			to_char(s.session_date_time, 'YY-MM') as yy_mm,
			count(*) as n_sessions
		from 
			sessions s 
		group by 
			to_char(s.session_date_time, 'YY-MM')
		order by 
			to_char(s.session_date_time, 'YY-MM')
		) 
	select
		sa.yy_mm,
		sc.n_canceled,
		sa.n_sessions
	from 
		sessions_all sa	
	left join sessions_canceled sc
	on 
		sa.yy_mm = sc.yy_mm
	) t1

--------------------------------------------------------------------------------------------------------------------------
-- 06.1 В какой день недели последнего полного месяца прошло больше всего встреч. 

select 
	to_char(s.session_date_time, 'day') as weekday,
	count(*) as n_sessions
from 
	sessions s 
where 
	to_char(s.session_date_time, 'YY-MM-DD') > '22-07-31'
	and to_char(s.session_date_time, 'YY-MM-DD') < '22-09-01'
group by 
	to_char(s.session_date_time, 'day')
order by 
	count(*) desc
	
-- 06.2 Самый загруженный день недели для каждого направления менторства. 
-- включая тип направления, день недели и количество встреч

with domain_rush_days as (-- код направления, самый загруженный день, количество завершенных сессий
	select 
		mentor_domain_id,
		weekday,
		n_sessions
	from (select -- добавление номера строки оконной функцией для фильтра 
		*,
		row_number() over(partition by mentor_domain_id) as rn
			from (-- количество завершенных сессий по дню недели и направлению менторства
					select 
						s.mentor_domain_id,
						to_char(s.session_date_time, 'day') as weekday,
						count(*) as n_sessions
					from 
						sessions s
					where 
						s.session_status = 'finished'
					group by 
						s.mentor_domain_id, 
							to_char(s.session_date_time, 'day')
					order by 
						s.mentor_domain_id, 
						count(*) desc
					) t1 
		)t2
	where 
		rn = 1
	)
select 
	d.name,
	drd.weekday,
	drd.n_sessions
from 
	domain d
left join domain_rush_days drd
on 
	d.id = drd.mentor_domain_id

--------------------------------------------------------------------------------------------------------------------------
-- 07. Дополнительный анализ
-- 07.1 Топ-10 регионов по количеству пользователей

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
from 
	region r 
join users_stat us
on 
	r.id  = us.region_id
order by 
	us.n_users desc
limit 10

-- 07.2 Количество менторов по направлению
/*запрос сработает т.к. все менторы проводили сессии, 
но безсессионные не попадут в результат -> вопрос к организации БД*/

with mentors_per_domain as (
			select 
				s.mentor_domain_id,
				count(distinct(s.mentor_id)) as n_mentors
			from 
				sessions s
			group by 
				s.mentor_domain_id
)
select 
	d.name, 
	mpd.n_mentors
from 
	domain d
left join mentors_per_domain mpd
on 
	d.id = mpd.mentor_domain_id
order by 
	n_mentors desc

-- 07.3 Запрос у менти на сессии по разным направлениям менторства
-- Как распределено количество сессий по направлениям менторства?

-- По какому количеству направлений менторства берутся встречи?

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
group by 
	n_domains
order by 
	n_domains desc

-- Меняется ли это в зависимости от отмены сессии?

select 
	n_domains,
	count(*) as n_sessions
from (
		select 
			s.mentee_id,
			count(distinct(s.mentor_domain_id)) as n_domains
		from 
			sessions s 
		where 
			s.session_status = 'canceled'
		group by 
			s.mentee_id 
		) t
group by 
	n_domains
order by 
	n_domains desc

/*Чаще всего отменяются сессии у менти, которые назначают по одному направлению менторства*/

-- Количество отмененных сессий по направлению менторства

with canceled_sessions_by_domain as (
		select 
			s.mentor_domain_id,
			count(*) as n_sessions_canceled
		from 
			sessions s 
		where 
			s.session_status = 'canceled'
		group by 
			s.mentor_domain_id
		)
select
	d.name,
	csbd.n_sessions_canceled
from 
	domain d
left join canceled_sessions_by_domain csbd
on 
	d.id = csbd.mentor_domain_id
order by 
	csbd.n_sessions_canceled desc

/* разброс количества отменных сессий по направлениям от 126 до 189 */