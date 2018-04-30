SELECT customerName, productCode, productName, COUNT(*),
  MIN(priceEach) as minPaid,
  MAX(priceEach) as maxPaid,
  MSRP
FROM customers    c
JOIN orders       o USING(customerNumber)
JOIN orderdetails d USING(orderNumber)
JOIN products     p USING(productCode)
WHERE customerNumber = 5275
GROUP BY productCode
ORDER BY COUNT(*) DESC
