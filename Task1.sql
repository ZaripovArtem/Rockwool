SELECT
    e.line_id AS "Линия",
    e.name AS "Название оборудования",
    CASE
        WHEN d.event_id IS NOT NULL THEN 'Простой'
        WHEN o.status = 'running' THEN 'В работе'
        WHEN o.status = 'paused' THEN 'Пауза'
        ELSE 'Свободно'
    END AS "Состояние",
    po.order_number AS "Заказ",
    o.operation_name AS "Операция",
    o.planned_qty AS "План",
    o.actual_qty AS "Сделано",
    ROUND(100.0 * o.actual_qty / o.planned_qty, 2) AS "Выполнение плана, %",
    CASE d.reason_code
        WHEN 'breakdown' THEN 'Поломка'
        WHEN 'setup' THEN 'Наладка'
        WHEN 'material' THEN 'Нет материала'
        WHEN 'operator' THEN 'Нет оператора'
        ELSE d.reason_code
    END AS "Причина простоя"
FROM equipment e
LEFT JOIN operations o
    ON o.equipment_id = e.equipment_id
    AND o.status IN ('running', 'paused')
    AND o.started_at <= LOCALTIMESTAMP
    AND (o.finished_at IS NULL OR o.finished_at > LOCALTIMESTAMP)
LEFT JOIN downtime_events d
    ON d.equipment_id = e.equipment_id
    AND d.start_time <= LOCALTIMESTAMP
    AND (d.end_time IS NULL OR d.end_time > LOCALTIMESTAMP)
LEFT JOIN production_orders po
    ON po.order_id = o.order_id
ORDER BY e.line_id, e.equipment_id;