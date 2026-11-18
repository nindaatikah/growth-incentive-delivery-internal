select city_name as city
from main.ng_delivery.dim_delivery_city
where food_delivery_launch_date is not null
group by 1
