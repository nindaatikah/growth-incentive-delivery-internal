-- =============================================================================
-- Daily signups and first-order activations by local / tourist / unknown phone
-- =============================================================================
-- Local: phone_anonymized equals the city country's calling code (356 in Malta).
-- Unknown: missing, blank, or 0. Everyone else is a tourist.
-- Signups use registration city and created_date_local.
-- New users use activation city and delivery_activation_ts_local.
-- Grain: date × country × city × user_type
-- =============================================================================

WITH phone_prefix AS (
    SELECT country_code, phone_prefix
    FROM VALUES
        ('ae','971'),('al','355'),('am','374'),('ao','244'),('ar','54'),('at','43'),
        ('au','61'),('az','994'),('ba','387'),('be','32'),('bf','226'),('bg','359'),
        ('bh','973'),('bi','257'),('bj','229'),('bo','591'),('br','55'),('bw','267'),
        ('by','375'),('ca','1'),('cd','243'),('cf','236'),('cg','242'),('ch','41'),
        ('ci','225'),('cl','56'),('cm','237'),('cn','86'),('co','57'),('cr','506'),
        ('cv','238'),('cy','357'),('cz','420'),('de','49'),('dj','253'),('dk','45'),
        ('do','1'),('dz','213'),('ec','593'),('ee','372'),('eg','20'),('eh','212'),
        ('er','291'),('es','34'),('et','251'),('fi','358'),('fo','298'),('fr','33'),
        ('ga','241'),('gb','44'),('ge','995'),('gh','233'),('gm','220'),('gn','224'),
        ('gq','240'),('gr','30'),('gt','502'),('gw','245'),('hn','504'),('hr','385'),
        ('hu','36'),('ie','353'),('il','972'),('in','91'),('iq','964'),('it','39'),
        ('jm','1'),('jo','962'),('ke','254'),('km','269'),('kw','965'),('kz','7'),
        ('lb','961'),('lk','94'),('lr','231'),('ls','266'),('lt','370'),('lu','352'),
        ('lv','371'),('ly','218'),('ma','212'),('md','373'),('me','382'),('mg','261'),
        ('mk','389'),('ml','223'),('mm','95'),('mr','222'),('mt','356'),('mu','230'),
        ('mw','265'),('mx','52'),('my','60'),('mz','258'),('na','264'),('ne','227'),
        ('ng','234'),('nl','31'),('no','47'),('np','977'),('nz','64'),('pa','507'),
        ('pe','51'),('ph','63'),('pk','92'),('pl','48'),('pr','1'),('pt','351'),
        ('py','595'),('qa','974'),('ro','40'),('rs','381'),('ru','7'),('rw','250'),
        ('sa','966'),('sc','248'),('sd','249'),('se','46'),('si','386'),('sk','421'),
        ('sl','232'),('sn','221'),('so','252'),('ss','211'),('st','239'),('sv','503'),
        ('sz','268'),('td','235'),('tg','228'),('th','66'),('tn','216'),('tr','90'),
        ('tv','688'),('tw','886'),('tz','255'),('ua','380'),('ug','256'),('us','1'),
        ('uy','598'),('uz','998'),('vn','84'),('xk','383'),('za','27'),('zm','260'),
        ('zw','263')
    AS t(country_code, phone_prefix)
),
signups AS (
    SELECT
        CAST(u.created_date_local AS DATE) AS order_date,
        LOWER(dc.country_code) AS country,
        dc.country_name,
        COALESCE(dc.city_name, 'Unknown') AS city_name,
        CASE
            WHEN CAST(b.phone_anonymized AS STRING) = p.phone_prefix THEN 'local'
            WHEN b.phone_anonymized IS NULL
              OR TRIM(CAST(b.phone_anonymized AS STRING)) IN ('', '0') THEN 'unknown_phone'
            ELSE 'tourist'
        END AS user_type,
        COUNT(DISTINCT u.user_id) AS signups
    FROM main.ng_delivery.dim_user_delivery u
    LEFT JOIN main.ng_public.user_user b
        ON u.user_id = b.id
    LEFT JOIN main.ng_delivery.dim_delivery_city dc
        ON u.city_id = dc.city_id
    LEFT JOIN phone_prefix p
        ON LOWER(dc.country_code) = p.country_code
    WHERE u.created_date_local >= DATE '2024-04-01'
      AND u.created_date_local < CURRENT_DATE
      AND COALESCE(u.user_is_bot, false) = false
      AND COALESCE(u.user_is_employee, false) = false
    GROUP BY 1, 2, 3, 4, 5
),
activations AS (
    SELECT
        CAST(u.delivery_activation_ts_local AS DATE) AS order_date,
        LOWER(dc.country_code) AS country,
        dc.country_name,
        COALESCE(dc.city_name, 'Unknown') AS city_name,
        CASE
            WHEN CAST(b.phone_anonymized AS STRING) = p.phone_prefix THEN 'local'
            WHEN b.phone_anonymized IS NULL
              OR TRIM(CAST(b.phone_anonymized AS STRING)) IN ('', '0') THEN 'unknown_phone'
            ELSE 'tourist'
        END AS user_type,
        COUNT(DISTINCT u.user_id) AS new_users
    FROM main.ng_delivery.dim_user_delivery u
    LEFT JOIN main.ng_public.user_user b
        ON u.user_id = b.id
    LEFT JOIN main.ng_delivery.dim_delivery_city dc
        ON u.delivery_activation_city_id = dc.city_id
    LEFT JOIN phone_prefix p
        ON LOWER(dc.country_code) = p.country_code
    WHERE CAST(u.delivery_activation_ts_local AS DATE) >= DATE '2024-04-01'
      AND CAST(u.delivery_activation_ts_local AS DATE) < CURRENT_DATE
      AND COALESCE(u.user_is_bot, false) = false
      AND COALESCE(u.user_is_employee, false) = false
    GROUP BY 1, 2, 3, 4, 5
)
SELECT
    COALESCE(s.order_date, a.order_date) AS order_date,
    COALESCE(s.country, a.country) AS country,
    COALESCE(s.country_name, a.country_name) AS country_name,
    COALESCE(s.city_name, a.city_name) AS city_name,
    COALESCE(s.user_type, a.user_type) AS user_type,
    COALESCE(s.signups, 0) AS signups,
    COALESCE(a.new_users, 0) AS new_users
FROM signups s
FULL OUTER JOIN activations a
    ON s.order_date = a.order_date
   AND s.country = a.country
   AND s.country_name = a.country_name
   AND s.city_name = a.city_name
   AND s.user_type = a.user_type
WHERE COALESCE(s.order_date, a.order_date) >= DATE '2024-04-01'
  AND COALESCE(s.order_date, a.order_date) < CURRENT_DATE
