
USE retail_assessment;
SELECT
    StoreID,
    StoreName,
    RegionRaw
FROM Stores
ORDER BY StoreID;

SELECT DISTINCT RegionRaw
FROM Stores;

CREATE TABLE Regions (
    RegionID INT PRIMARY KEY,
    RegionName VARCHAR(50) UNIQUE
);



INSERT INTO Regions (RegionID, RegionName)
VALUES
(1, 'North'),
(2, 'South'),
(3, 'West');


ALTER TABLE Stores
ADD COLUMN RegionID INT;



SET SQL_SAFE_UPDATES = 0;

UPDATE Stores
SET RegionID = CASE
    WHEN UPPER(TRIM(RegionRaw)) IN ('N', 'NORTH') THEN 1
    WHEN UPPER(TRIM(RegionRaw)) IN ('S', 'SOUTH') THEN 2
    WHEN UPPER(TRIM(RegionRaw)) IN ('WEST', 'W') THEN 3
    ELSE NULL
END;

SET SQL_SAFE_UPDATES = 1;



ALTER TABLE Stores
ADD CONSTRAINT fk_stores_regions
FOREIGN KEY (RegionID) REFERENCES Regions(RegionID);



SELECT
    s.StoreID,
    s.StoreName,
    s.RegionRaw,
    s.RegionID,
    r.RegionName
FROM Stores s
LEFT JOIN Regions r
    ON s.RegionID = r.RegionID
ORDER BY s.StoreID;


-- 09. Check unmapped stores

SELECT
    StoreID,
    StoreName,
    RegionRaw
FROM Stores
WHERE RegionID IS NULL;


-- Q2. DUPLICATE DATA CLEANING


SELECT COUNT(*) AS RawTotalRows
FROM OrderItems_Raw;




SELECT
    OrderItemID,
    COUNT(*) AS DuplicateCount
FROM OrderItems_Raw
GROUP BY OrderItemID
HAVING COUNT(*) > 1;




INSERT INTO OrderItems
    (OrderItemID, OrderID, ProductID, Quantity, UnitPrice, LoadedAt)
SELECT
    OrderItemID,
    OrderID,
    ProductID,
    Quantity,
    UnitPrice,
    LoadedAt
FROM (
    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY OrderItemID
            ORDER BY LoadedAt DESC
        ) AS rn
    FROM OrderItems_Raw
) AS ranked
WHERE rn = 1;


SELECT COUNT(*) AS CleanedTotalRows
FROM OrderItems;


SELECT
    OrderItemID,
    COUNT(*) AS DuplicateCount
FROM OrderItems
GROUP BY OrderItemID
HAVING COUNT(*) > 1;



-- Q4. ORDERS WITH MATCHING CUSTOMERS


SELECT
    o.OrderID,
    o.OrderDate,
    o.CustomerID,
    c.CustomerName,
    o.StoreID,
    o.OrderStatus
FROM Orders o
INNER JOIN Customers c
    ON o.CustomerID = c.CustomerID
ORDER BY o.OrderID;


-- Q5. ORDERS WITH UNMATCHED CUSTOMER IDs


SELECT
    o.OrderID,
    o.OrderDate,
    o.CustomerID,
    o.StoreID,
    o.OrderStatus
FROM Orders o
LEFT JOIN Customers c
    ON o.CustomerID = c.CustomerID
WHERE c.CustomerID IS NULL
ORDER BY o.OrderID;



-- Q6. CUSTOMERS WITHOUT ORDERS


SELECT
    c.CustomerID,
    c.CustomerName,
    c.SignupDate
FROM Customers c
LEFT JOIN Orders o
    ON c.CustomerID = o.CustomerID
WHERE o.OrderID IS NULL
ORDER BY c.CustomerID;


-- Q7. ORDER ITEMS WITH MULTIPLE RETURN TRANSACTIONS


SELECT
    oi.OrderItemID,
    oi.OrderID,
    COUNT(r.ReturnID) AS ReturnTransactions,
    SUM(r.ReturnQuantity) AS TotalReturnedQuantity
FROM OrderItems oi
JOIN Returns r
    ON oi.OrderItemID = r.OrderItemID
GROUP BY
    oi.OrderItemID,
    oi.OrderID
HAVING COUNT(r.ReturnID) > 1
ORDER BY oi.OrderItemID;


-- Q8. REGIONAL SALES ANALYSIS


WITH Gross AS (
    SELECT
        r.RegionID,
        r.RegionName,
        COUNT(DISTINCT o.OrderID) AS CompletedOrderCount,
        SUM(oi.Quantity * oi.UnitPrice) AS GrossSales
    FROM Orders o
    JOIN Stores s
        ON o.StoreID = s.StoreID
    JOIN Regions r
        ON s.RegionID = r.RegionID
    JOIN OrderItems oi
        ON o.OrderID = oi.OrderID
    WHERE o.OrderStatus = 'Completed'
      AND o.OrderDate >= '2026-10-01'
      AND o.OrderDate < '2026-11-01'
    GROUP BY r.RegionID, r.RegionName
),

ReturnsByRegion AS (
    SELECT
        r.RegionID,
        SUM(ret.ReturnQuantity * oi.UnitPrice) AS ReturnValue
    FROM Returns ret
    JOIN OrderItems oi
        ON ret.OrderItemID = oi.OrderItemID
    JOIN Orders o
        ON oi.OrderID = o.OrderID
    JOIN Stores s
        ON o.StoreID = s.StoreID
    JOIN Regions r
        ON s.RegionID = r.RegionID
    WHERE o.OrderStatus = 'Completed'
      AND ret.ReturnDate >= '2026-10-01'
      AND ret.ReturnDate < '2026-11-01'
    GROUP BY r.RegionID
)

SELECT
    g.RegionName,
    g.CompletedOrderCount,
    g.GrossSales,
    COALESCE(rb.ReturnValue, 0) AS ReturnValue,
    g.GrossSales - COALESCE(rb.ReturnValue, 0) AS NetSales
FROM Gross g
LEFT JOIN ReturnsByRegion rb
    ON g.RegionID = rb.RegionID
ORDER BY g.RegionName;



-- Q9. REGIONAL PERFORMANCE COMPARISON


WITH Gross AS (
    SELECT
        r.RegionID,
        r.RegionName,
        SUM(oi.Quantity * oi.UnitPrice) AS GrossSales
    FROM Orders o
    JOIN Stores s ON o.StoreID = s.StoreID
    JOIN Regions r ON s.RegionID = r.RegionID
    JOIN OrderItems oi ON o.OrderID = oi.OrderID
    WHERE o.OrderStatus = 'Completed'
      AND o.OrderDate >= '2026-10-01'
      AND o.OrderDate < '2026-11-01'
    GROUP BY r.RegionID, r.RegionName
),

ReturnsByRegion AS (
    SELECT
        r.RegionID,
        SUM(ret.ReturnQuantity * oi.UnitPrice) AS ReturnValue
    FROM Returns ret
    JOIN OrderItems oi ON ret.OrderItemID = oi.OrderItemID
    JOIN Orders o ON oi.OrderID = o.OrderID
    JOIN Stores s ON o.StoreID = s.StoreID
    JOIN Regions r ON s.RegionID = r.RegionID
    WHERE o.OrderStatus = 'Completed'
      AND ret.ReturnDate >= '2026-10-01'
      AND ret.ReturnDate < '2026-11-01'
    GROUP BY r.RegionID
),

RegionalSales AS (
    SELECT
        g.RegionID,
        g.RegionName,
        g.GrossSales,
        COALESCE(rb.ReturnValue, 0) AS ReturnValue,
        g.GrossSales - COALESCE(rb.ReturnValue, 0) AS NetSales
    FROM Gross g
    LEFT JOIN ReturnsByRegion rb
        ON g.RegionID = rb.RegionID
),

RankedSales AS (
    SELECT
        *,
        RANK() OVER (ORDER BY GrossSales DESC) AS GrossRank,
        RANK() OVER (ORDER BY NetSales DESC) AS NetRank,
        GrossSales - LEAD(GrossSales) OVER (
            ORDER BY GrossSales DESC, RegionName
        ) AS GrossSalesGap,
        NetSales - LEAD(NetSales) OVER (
            ORDER BY NetSales DESC, RegionName
        ) AS NetSalesGap
    FROM RegionalSales
)

SELECT
    RegionName,
    GrossSales,
    ReturnValue,
    NetSales,
    GrossRank,
    NetRank,
    GrossSalesGap,
    NetSalesGap
FROM RankedSales
ORDER BY GrossRank, RegionName;



-- Q10. STORE-WISE SALES ANALYSIS


WITH GrossSales AS (
    SELECT
        o.StoreID,
        SUM(oi.Quantity * oi.UnitPrice) AS GrossSales
    FROM Orders o
    JOIN OrderItems oi
        ON o.OrderID = oi.OrderID
    WHERE o.OrderStatus = 'Completed'
      AND o.OrderDate >= '2026-10-01'
      AND o.OrderDate < '2026-11-01'
    GROUP BY o.StoreID
),

ReturnSales AS (
    SELECT
        o.StoreID,
        SUM(ret.ReturnQuantity * oi.UnitPrice) AS ReturnValue
    FROM Returns ret
    JOIN OrderItems oi
        ON ret.OrderItemID = oi.OrderItemID
    JOIN Orders o
        ON oi.OrderID = o.OrderID
    WHERE o.OrderStatus = 'Completed'
      AND ret.ReturnDate >= '2026-10-01'
      AND ret.ReturnDate < '2026-11-01'
    GROUP BY o.StoreID
),

StoreSales AS (
    SELECT
        r.RegionName,
        s.StoreID,
        s.StoreName,
        COALESCE(g.GrossSales, 0) AS GrossSales,
        COALESCE(rs.ReturnValue, 0) AS ReturnValue,
        COALESCE(g.GrossSales, 0)
            - COALESCE(rs.ReturnValue, 0) AS NetSales
    FROM Stores s
    JOIN Regions r
        ON s.RegionID = r.RegionID
    LEFT JOIN GrossSales g
        ON s.StoreID = g.StoreID
    LEFT JOIN ReturnSales rs
        ON s.StoreID = rs.StoreID
),

RankedStores AS (
    SELECT *,
        RANK() OVER (
            PARTITION BY RegionName
            ORDER BY NetSales DESC
        ) AS StoreRank
    FROM StoreSales
)

SELECT
    RegionName,
    StoreID,
    StoreName,
    GrossSales,
    ReturnValue,
    NetSales,
    StoreRank
FROM RankedStores
ORDER BY RegionName, StoreRank, StoreID;



-- Q11. RETURN VALUE BY PRODUCT CATEGORY


WITH RegionReturns AS (
    SELECT
        r.RegionID,
        r.RegionName,
        SUM(ret.ReturnQuantity * oi.UnitPrice) AS TotalReturnValue
    FROM Returns ret
    JOIN OrderItems oi
        ON ret.OrderItemID = oi.OrderItemID
    JOIN Orders o
        ON oi.OrderID = o.OrderID
    JOIN Stores s
        ON o.StoreID = s.StoreID
    JOIN Regions r
        ON s.RegionID = r.RegionID
    WHERE o.OrderStatus = 'Completed'
      AND ret.ReturnDate >= '2026-10-01'
      AND ret.ReturnDate < '2026-11-01'
    GROUP BY r.RegionID, r.RegionName
),

HighestReturnRegion AS (
    SELECT
        RegionID,
        RegionName
    FROM (
        SELECT
            RegionID,
            RegionName,
            RANK() OVER (
                ORDER BY TotalReturnValue DESC
            ) AS RegionRank
        FROM RegionReturns
    ) ranked
    WHERE RegionRank = 1
)

SELECT
    h.RegionName,
    p.Category,
    SUM(ret.ReturnQuantity * oi.UnitPrice) AS ReturnValue
FROM HighestReturnRegion h
JOIN Stores s
    ON h.RegionID = s.RegionID
JOIN Orders o
    ON s.StoreID = o.StoreID
JOIN OrderItems oi
    ON o.OrderID = oi.OrderID
JOIN Returns ret
    ON oi.OrderItemID = ret.OrderItemID
JOIN Products p
    ON oi.ProductID = p.ProductID
WHERE o.OrderStatus = 'Completed'
  AND ret.ReturnDate >= '2026-10-01'
  AND ret.ReturnDate < '2026-11-01'
GROUP BY
    h.RegionName,
    p.Category
ORDER BY ReturnValue DESC, p.Category ASC;


