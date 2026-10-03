-- Active Auctions View

CREATE VIEW ActiveAuctions AS
SELECT 
    i.ItemID,
    i.ItemName,
    i.CurrentPrice,
    i.NumberOfBids,
    i.EndTime,
    u.Username AS SellerName,
    TIMESTAMPDIFF(HOUR, CURRENT_TIMESTAMP, i.EndTime) AS HoursRemaining
FROM Items i
JOIN Users u ON i.SellerID = u.UserID
WHERE i.EndTime > CURRENT_TIMESTAMP
  AND i.ItemID NOT IN (SELECT ItemID FROM Auctions WHERE PaymentStatus = 'COMPLETED');


-- User Ratings View

CREATE VIEW UserRatings AS
SELECT 
    sr.SellerID,
    u.Username,
    COUNT(*) AS TotalReviews,
    ROUND(AVG(sr.Rating), 2) AS AverageRating,
    COUNT(CASE WHEN sr.Rating = 5 THEN 1 END) AS FiveStarReviews
FROM SellerReviews sr
JOIN Users u ON sr.SellerID = u.UserID
GROUP BY sr.SellerID, u.Username;


-- Auction History View

CREATE VIEW AuctionHistory AS
SELECT 
    i.ItemID,
    i.ItemName,
    i.StartTime,
    i.EndTime,
    i.StartingPrice,
    i.CurrentPrice AS FinalPrice,
    i.NumberOfBids,
    s.Username AS SellerName,
    b.Username AS WinnerName,
    a.PaymentStatus,
    i.ShippingStatus
FROM Items i
LEFT JOIN Auctions a ON i.ItemID = a.ItemID
LEFT JOIN Users s ON i.SellerID = s.UserID
LEFT JOIN Users b ON a.WinningBidderID = b.UserID
WHERE i.EndTime < CURRENT_TIMESTAMP;


-- Recent Activity View

CREATE VIEW RecentActivity AS
SELECT 
    'BID' AS ActivityType,
    b.BidTime AS ActivityTime,
    i.ItemID,
    i.ItemName,
    u.Username,
    b.BidAmount AS Amount
FROM Bids b
JOIN Items i ON b.ItemID = i.ItemID
JOIN Users u ON b.BidderID = u.UserID

UNION ALL

SELECT 
    'PAYMENT' AS ActivityType,
    l.CreatedAt AS ActivityTime,
    l.RelatedEntityID AS ItemID,
    i.ItemName,
    u.Username,
    i.CurrentPrice AS Amount
FROM SystemLogs l
JOIN Items i ON l.RelatedEntityID = i.ItemID
JOIN Auctions a ON i.ItemID = a.ItemID
JOIN Users u ON a.WinningBidderID = u.UserID
WHERE l.EventType = 'PAYMENT_PROCESSED'

ORDER BY ActivityTime DESC
LIMIT 100;