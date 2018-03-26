Find the Top 10 clients for a given employee, with order count, in the last 3 months:


-- ORIGINAL --  (~23 sec)
EXPLAIN EXTENDED
SELECT customerNumber, contactFirstName, contactLastName,
  COUNT(DISTINCT orderNumber) as total_orders,
  MAX(orderDate) as last_order,
  SUM(priceEach * quantityOrdered) as total_order_value,
  SUM(priceEach * quantityOrdered)/COUNT(DISTINCT orderNumber) as average_order_value
FROM employees    e
JOIN customers    c ON (c.salesRepEmployeeNumber = e.employeeNumber)
JOIN orders       o USING (customerNumber)
JOIN orderdetails d USING (orderNumber)
WHERE e.email = 'abow@classicmodelcars.com'
  AND o.orderDate > DATE_SUB(NOW(), INTERVAL 90 DAY)
GROUP BY customerNumber
ORDER BY COUNT(DISTINCT orderNumber) DESC, customerNumber
LIMIT 100



-- REMOVE employee table in JOIN, by resolving ID (~23 sec)
--    ==> DID NOT HELP
SELECT customerNumber, contactFirstName, contactLastName,
  COUNT(DISTINCT orderNumber) as total_orders,
  MAX(orderDate) as last_order,
  SUM(priceEach * quantityOrdered) as total_order_value,
  SUM(priceEach * quantityOrdered)/COUNT(DISTINCT orderNumber) as average_order_value
FROM customers    c
JOIN orders       o USING (customerNumber)
JOIN orderdetails d USING (orderNumber)
WHERE c.salesRepEmployeeNumber = 1143
  AND o.orderDate > DATE_SUB(NOW(), INTERVAL 90 DAY)
GROUP BY customerNumber
ORDER BY COUNT(DISTINCT orderNumber) DESC, customerNumber
LIMIT 100


-- Same Query, but INDEX the orderDate column (~22 sec)

ALTER TABLE orders ADD INDEX (orderDate);

--    ==> DID NOT HELP
SELECT customerNumber, contactFirstName, contactLastName,
  COUNT(DISTINCT orderNumber) as total_orders,
  MAX(orderDate) as last_order,
  SUM(priceEach * quantityOrdered) as total_order_value,
  SUM(priceEach * quantityOrdered)/COUNT(DISTINCT orderNumber) as average_order_value
FROM employees    e
JOIN customers    c ON (c.salesRepEmployeeNumber = e.employeeNumber)
JOIN orders       o USING (customerNumber)
JOIN orderdetails d USING (orderNumber)
WHERE e.email = 'abow@classicmodelcars.com'
  AND o.orderDate > DATE_SUB(NOW(), INTERVAL 90 DAY)
GROUP BY customerNumber
ORDER BY COUNT(DISTINCT orderNumber) DESC, customerNumber
LIMIT 100



-- Force it to use the index (search by date first) (~98 sec)
--     ==> WORSE
--  Tho, with a SMALL time range (4 days), it runs in 3 sec
SELECT customerNumber, contactFirstName, contactLastName,
  COUNT(DISTINCT orderNumber) as total_orders,
  MAX(orderDate) as last_order,
  SUM(priceEach * quantityOrdered) as total_order_value,
  SUM(priceEach * quantityOrdered)/COUNT(DISTINCT orderNumber) as average_order_value
FROM customers    c
JOIN orders       o USING (customerNumber) USE INDEX (orderDate)
JOIN orderdetails d USING (orderNumber)
WHERE c.salesRepEmployeeNumber = 1143
  AND o.orderDate > DATE_SUB(NOW(), INTERVAL 90 DAY)
GROUP BY customerNumber
ORDER BY COUNT(DISTINCT orderNumber) DESC, customerNumber
LIMIT 100



-- Pre-caching last order num in customer (~9 sec)
--       ==> BETTER now, but still pretty slow
ALTER TABLE customers ADD lastOrder DATE  NULL  AFTER creditLimit;
UPDATE customers
  SET lastOrder = (SELECT MAX(orderDate) FROM orders o WHERE o.customerNumber = customers.customerNumber);

ALTER TABLE customers ADD INDEX rep_last_order_idx (salesRepEmployeeNumber,lastOrder);

SELECT customerNumber, contactFirstName, contactLastName,
  COUNT(DISTINCT orderNumber) as total_orders,
  MAX(orderDate) as last_order,
  SUM(priceEach * quantityOrdered) as total_order_value,
  SUM(priceEach * quantityOrdered)/COUNT(DISTINCT orderNumber) as average_order_value
FROM customers    c
JOIN orders       o USING (customerNumber)
JOIN orderdetails d USING (orderNumber)
WHERE c.salesRepEmployeeNumber = 1143
  AND c.lastOrder > DATE_SUB(NOW(), INTERVAL 90 DAY)
  AND o.orderDate > DATE_SUB(NOW(), INTERVAL 90 DAY)
GROUP BY customerNumber
ORDER BY COUNT(DISTINCT orderNumber) DESC, customerNumber
LIMIT 100



-- Now the explain plan looks OK, but it's still pretty slow...
c range rep_last_order_idx  9 71804 100.00  Using index condition
o ref   customerNumber      4     3  10.69  Using where
d ref   PRIMARY             4     1 100.00  NULL




-- Rule out Order Details Join, remove it (~9 sec)
--  It was a good idea to try, as it's a HUGE table, but...
--    ==> It didn't help
SELECT customerNumber, contactFirstName, contactLastName,
  COUNT(DISTINCT orderNumber) as total_orders,
  MAX(orderDate) as last_order
FROM customers    c
JOIN orders       o USING (customerNumber)
WHERE c.salesRepEmployeeNumber = 1143
  AND c.lastOrder > DATE_SUB(NOW(), INTERVAL 90 DAY)
  AND o.orderDate > DATE_SUB(NOW(), INTERVAL 90 DAY)
GROUP BY customerNumber
ORDER BY COUNT(DISTINCT orderNumber) DESC, customerNumber
LIMIT 100




-- Try indexing the lookup on orders(custnum + date): (~4 sec)
--   ==> BETTER!
ALTER TABLE `orders` ADD INDEX cust_date_idx (`customerNumber`, `orderDate`);

SELECT customerNumber, contactFirstName, contactLastName,
  COUNT(DISTINCT orderNumber) as total_orders,
  MAX(orderDate) as last_order,
  SUM(priceEach * quantityOrdered) as total_order_value,
  SUM(priceEach * quantityOrdered)/COUNT(DISTINCT orderNumber) as average_order_value
FROM customers    c
JOIN orders       o USING (customerNumber)
JOIN orderdetails d USING (orderNumber)
WHERE c.salesRepEmployeeNumber = 1143
  AND c.lastOrder > DATE_SUB(NOW(), INTERVAL 90 DAY)
  AND o.orderDate > DATE_SUB(NOW(), INTERVAL 90 DAY)
GROUP BY customerNumber
ORDER BY COUNT(DISTINCT orderNumber) DESC, customerNumber
LIMIT 100



--  Add back in employee (~9 sec)
--     ==> WORSE.  It's doing employee join different in EXPLAIN
SELECT customerNumber, contactFirstName, contactLastName,
  COUNT(DISTINCT orderNumber) as total_orders,
  MAX(orderDate) as last_order,
  SUM(priceEach * quantityOrdered) as total_order_value,
  SUM(priceEach * quantityOrdered)/COUNT(DISTINCT orderNumber) as average_order_value
FROM employees    e
JOIN customers    c ON (c.salesRepEmployeeNumber = e.employeeNumber)
JOIN orders       o USING (customerNumber)
JOIN orderdetails d USING (orderNumber)
WHERE e.email = 'abow@classicmodelcars.com'
  AND c.lastOrder > DATE_SUB(NOW(), INTERVAL 90 DAY)
  AND o.orderDate > DATE_SUB(NOW(), INTERVAL 90 DAY)
GROUP BY customerNumber
ORDER BY COUNT(DISTINCT orderNumber) DESC, customerNumber
LIMIT 100




--  Pre-Query employee EMAIL -> Num (~4 sec)
--     ==> BETTER -- BACK to fastest time again
SELECT customerNumber, contactFirstName, contactLastName,
  COUNT(DISTINCT orderNumber) as total_orders,
  MAX(orderDate) as last_order,
  SUM(priceEach * quantityOrdered) as total_order_value,
  SUM(priceEach * quantityOrdered)/COUNT(DISTINCT orderNumber) as average_order_value
FROM employees    e
JOIN customers    c ON (c.salesRepEmployeeNumber = e.employeeNumber)
JOIN orders       o USING (customerNumber)
JOIN orderdetails d USING (orderNumber)
WHERE c.salesRepEmployeeNumber =
    (SELECT employeeNumber FROM employees WHERE email = 'abow@classicmodelcars.com')
  AND c.lastOrder > DATE_SUB(NOW(), INTERVAL 90 DAY)
  AND o.orderDate > DATE_SUB(NOW(), INTERVAL 90 DAY)
GROUP BY customerNumber
ORDER BY COUNT(DISTINCT orderNumber) DESC, customerNumber
LIMIT 100



--  =====================
--          NOTE!
--  =====================
--
-- After optimizing make sure to compare the records returned from your start 
-- to the data you get from your final query.  It's very easy to change the 
-- output result as you play with things...
-- 

