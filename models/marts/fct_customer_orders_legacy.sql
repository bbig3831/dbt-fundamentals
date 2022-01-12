with

-- Import CTEs
orders as (
    select * from {{ ref('int_orders') }}
),

customers as (
    select * from {{ ref('stg_jaffle_shop__customers') }}
),

-- Logical CTEs
customer_orders as (
    select
        orders.*,
        customers.full_name,
        customers.surname,
        customers.givenname,

        -- Customer-level aggregations
        min(orders.order_date) over (
            partition by orders.customer_id
        ) as first_order_date, 
        min(orders.valid_order_date) over (
            partition by orders.customer_id
        ) as first_non_returned_order_date,
        max(orders.valid_order_date) over (
            partition by orders.customer_id
        ) as most_recent_non_returned_order_date,
        count(*) over (
            partition by orders.customer_id
        ) as order_count,
        sum(nvl2(orders.valid_order_date, 1, 0)) as non_returned_order_count,
        sum(nvl2(orders.valid_order_date, orders.order_value_dollars, 0)) as total_lifetime_value,
        sum(nvl2(orders.valid_order_date, orders.order_value_dollars, 0)) / 
        nullif(count(
            nvl2(orders.valid_order_date, 1, 0)
        )) as avg_non_returned_order_value,
        array_agg(distinct a.id) as order_ids

    from orders
    inner join customers on orders.customer_id = customers.customer_id
)


-- Marts
customer_order_history as (

    select 
        customers.customer_id,
        customers.full_name,
        customers.surname,
        customers.givenname,
        min(orders.order_date) as first_order_date,
        min(orders.valid_order_date) as first_non_returned_order_date,
        max(orders.valid_order_date) as most_recent_non_returned_order_date,
        coalesce(max(user_order_seq), 0) as order_count,
        coalesce(
            count(case when orders.valid_order_date is not null then 1 end), 0
        ) as non_returned_order_count,
        sum(
            case 
                when orders.valid_order_date is not null then orders.order_value_dollars
                else 0 
            end
        ) as total_lifetime_value,
        sum(
            case 
                when orders.valid_order_date is not null then orders.order_value_dollars 
                else 0 
            end
        ) / nullif(count(
            case when orders.valid_order_date is not null then 1 end
            ), 0
        ) as avg_non_returned_order_value,
        array_agg(distinct a.id) as order_ids

    from orders a
        join customers on orders.user_id = customers.id
        left outer join payments c on orders.order_id = payments.orderid
    where 
        a.status not in ('pending') 
        and c.status != 'fail'
    group by customers.customer_id, customers.full_name, customers.surname, customers.givenname
),

-- Final CTE
final as (
    select 
        orders.order_id,
        orders.customer_id,
        surname,
        givenname,
        first_order_date,
        order_count,
        total_lifetime_value,
        orders.order_value_dollars,
        orders.order_status,
        payments.payment_status
    from orders
        join customers on orders.user_id = customers.id
        join customer_order_history on orders.user_id = customer_order_history.customer_id
)
-- Simple select statement
select *
from final

