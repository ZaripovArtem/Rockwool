WITH
lines AS (
    SELECT DISTINCT line_id
    FROM equipment
),
orders_last_30_days AS (
    SELECT order_id, planned_qty
    FROM production_orders
    WHERE status IN ('planned', 'in_progress', 'done')
      AND planned_end >= CURRENT_DATE - 30
      AND planned_end < LOCALTIMESTAMP
),
final_operations AS (
    SELECT
        o.operation_id,
        o.order_id,
        o.equipment_id,
        o.actual_qty AS output_qty
    FROM operations o
    LEFT JOIN operations later_operation
        ON later_operation.order_id = o.order_id
        AND later_operation.operation_id > o.operation_id
    WHERE later_operation.operation_id IS NULL
      AND o.order_id IN (SELECT order_id FROM orders_last_30_days)
),
scrap_operation AS (
    SELECT operation_id, SUM(qty) AS scrap_qty
    FROM scrap_events
    GROUP BY operation_id
),
downtime_last_30_days AS (
    SELECT
        e.line_id,
        d.reason_code,
        EXTRACT(EPOCH FROM
            LEAST(COALESCE(d.end_time, LOCALTIMESTAMP), LOCALTIMESTAMP)
            - GREATEST(d.start_time, CURRENT_DATE - 30)
        ) / 3600 AS hours
    FROM downtime_events d
    LEFT JOIN equipment e
        ON e.equipment_id = d.equipment_id
    WHERE d.start_time < LOCALTIMESTAMP
      AND (d.end_time IS NULL OR d.end_time > CURRENT_DATE - 30)
),
downtime_line AS (
    SELECT
        line_id,
        ROUND(SUM(hours), 2) AS total_hours,
        ROUND(COALESCE(SUM(hours) FILTER (WHERE reason_code = 'breakdown'), 0), 2) AS breakdown_hours,
        ROUND(COALESCE(SUM(hours) FILTER (WHERE reason_code = 'setup'), 0), 2) AS setup_hours,
        ROUND(COALESCE(SUM(hours) FILTER (WHERE reason_code = 'material'), 0), 2) AS material_hours,
        ROUND(COALESCE(SUM(hours) FILTER (WHERE reason_code = 'operator'), 0), 2) AS operator_hours
    FROM downtime_last_30_days
    GROUP BY line_id
),
line_analytics AS (
    SELECT
        l.line_id,
        COUNT(DISTINCT e.equipment_id) * EXTRACT(EPOCH FROM LOCALTIMESTAMP - (CURRENT_DATE - 30)) / 3600 AS planned_hours,
        COUNT(ol.order_id) AS orders_count,
        COALESCE(SUM(ol.planned_qty), 0) AS planned_qty,
        COALESCE(SUM(fo.output_qty), 0) AS output_qty,
        COALESCE(SUM(so.scrap_qty), 0) AS scrap_qty,
        COALESCE(dl.total_hours, 0) AS downtime_hours,
        COALESCE(dl.breakdown_hours, 0) AS breakdown_hours,
        COALESCE(dl.setup_hours, 0) AS setup_hours,
        COALESCE(dl.material_hours, 0) AS material_hours,
        COALESCE(dl.operator_hours, 0) AS operator_hours
    FROM lines l
    LEFT JOIN equipment e
        ON e.line_id = l.line_id
    LEFT JOIN final_operations fo
        ON fo.equipment_id = e.equipment_id
    LEFT JOIN orders_last_30_days ol
        ON ol.order_id = fo.order_id
    LEFT JOIN scrap_operation so
        ON so.operation_id = fo.operation_id
    LEFT JOIN downtime_line dl
        ON dl.line_id = l.line_id
    GROUP BY
        l.line_id,
        dl.total_hours,
        dl.breakdown_hours,
        dl.setup_hours,
        dl.material_hours,
        dl.operator_hours
),
line_oee AS (
    SELECT
        line_id,
        (planned_hours - downtime_hours) / NULLIF(planned_hours, 0) AS availability,
        LEAST(1.0 * output_qty / NULLIF(planned_qty, 0), 1) AS performance,
        1.0 * (output_qty - scrap_qty) / NULLIF(output_qty, 0) AS quality
    FROM line_analytics
)
SELECT
    la.line_id AS "Линия",
    la.orders_count AS "Заказов",
    la.planned_qty AS "План",
    la.output_qty AS "Выработка",
    ROUND(100.0 * la.output_qty / NULLIF(la.planned_qty, 0), 2) AS "Выполнение плана, %",
    la.scrap_qty AS "Брак",
    la.output_qty - la.scrap_qty AS "Годные",
    ROUND(100 * oee.quality, 2) AS "Доля годной, %",
    la.downtime_hours AS "Простои всего, ч",
    la.breakdown_hours AS "Поломка, ч",
    la.setup_hours AS "Наладка, ч",
    la.material_hours AS "Нет материала, ч",
    la.operator_hours AS "Нет оператора, ч",
    ROUND(100 * oee.availability * oee.performance * oee.quality, 2) AS "OEE, %"
FROM line_analytics la
LEFT JOIN line_oee oee
    ON oee.line_id = la.line_id
ORDER BY la.line_id;