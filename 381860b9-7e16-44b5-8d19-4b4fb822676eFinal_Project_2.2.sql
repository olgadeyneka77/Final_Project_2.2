WITH cte_monthly AS (
   SELECT
       user_id,
       game_name,
       DATE_TRUNC('month', payment_date)::date AS payment_month,
       SUM(revenue_amount_usd) AS revenue_amount_usd
   FROM project.games_payments
   GROUP BY user_id, game_name, DATE_TRUNC('month', payment_date)::date
),
cte_lag_lead AS (
   SELECT
       user_id,
       game_name,
       payment_month,
       revenue_amount_usd,
       MIN(payment_month) OVER (PARTITION BY user_id, game_name) AS first_payment_month,
       LAG(payment_month) OVER (PARTITION BY user_id, game_name ORDER BY payment_month) AS prev_payment_month,
       LAG(revenue_amount_usd) OVER (PARTITION BY user_id, game_name ORDER BY payment_month) AS prev_revenue_amount,
       LEAD(payment_month) OVER (PARTITION BY user_id, game_name ORDER BY payment_month) AS next_payment_month
   FROM cte_monthly
),
-- Додаємо CTE для отримання унікальних характеристик користувачів з таблиці games_paid_users
cte_users_unique AS (
   SELECT DISTINCT ON (user_id, game_name)
       user_id,
       game_name,
       language,
       has_older_device_model,
       age
   FROM project.games_paid_users
   ORDER BY user_id, game_name
)
SELECT
   m.user_id,
   m.game_name,
   m.payment_month,
   m.revenue_amount_usd AS mrr,
   CASE
       WHEN m.payment_month = MIN(m.payment_month) OVER (PARTITION BY m.user_id, m.game_name)
       THEN m.revenue_amount_usd
   END AS new_mrr,
   CASE
       WHEN m.prev_payment_month IS NOT NULL
            AND m.payment_month = (m.prev_payment_month + INTERVAL '1 month')
            AND m.revenue_amount_usd > m.prev_revenue_amount
       THEN m.revenue_amount_usd - m.prev_revenue_amount
   END AS expansion_mrr,
   CASE
       WHEN m.prev_payment_month IS NOT NULL
            AND m.payment_month = (m.prev_payment_month + INTERVAL '1 month')
            AND m.revenue_amount_usd < m.prev_revenue_amount
       THEN m.revenue_amount_usd - m.prev_revenue_amount
   END AS contraction_mrr,
   CASE
       WHEN m.next_payment_month IS NULL
            OR m.next_payment_month > (m.payment_month + INTERVAL '1 month')
       THEN 1
   END AS is_churned_user,
   CASE
       WHEN m.next_payment_month IS NULL
            OR m.next_payment_month > (m.payment_month + INTERVAL '1 month')
       THEN m.revenue_amount_usd
   END AS churned_revenue,
   CASE
       WHEN m.next_payment_month IS NULL
            OR m.next_payment_month > (m.payment_month + INTERVAL '1 month')
       THEN (m.payment_month + INTERVAL '1 month')::date
   END AS churn_month,
   -- Поля для фільтрів у Tableau
   u.language,
   u.has_older_device_model,
   u.age
FROM cte_lag_lead m
LEFT JOIN cte_users_unique u
 ON m.user_id = u.user_id
 AND m.game_name = u.game_name;


