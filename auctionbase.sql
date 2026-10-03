CREATE DATABASE IF NOT EXISTS auctionbase;
USE auctionbase;

-- 1. Users identity table

CREATE TABLE Users (
    UserID      INT          PRIMARY KEY,
    Username    VARCHAR(50)  NOT NULL UNIQUE,
    Email       VARCHAR(100) NOT NULL UNIQUE,
    Name        VARCHAR(100) NOT NULL,
    Address     VARCHAR(200),
    PhoneNumber VARCHAR(20),
    IsSeller    BOOLEAN      NOT NULL DEFAULT FALSE,
    IsBuyer     BOOLEAN      NOT NULL DEFAULT FALSE,
    RegistrationDate DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    LastLoginDate    DATETIME,

    CONSTRAINT chk_user_role CHECK (IsSeller = TRUE OR IsBuyer = TRUE)
);

-- 2. Categories

CREATE TABLE Categories (
    CategoryID   INT          PRIMARY KEY,
    CategoryName VARCHAR(100) NOT NULL UNIQUE,
    CategoryDescription TEXT
);

-- 3. Items one item per auction

CREATE TABLE Items (
    ItemID        INT           PRIMARY KEY,
    ItemName      VARCHAR(255)  NOT NULL,
    SellerID      INT           NOT NULL,
    Location      VARCHAR(255),
    Country       VARCHAR(100),
    Description   TEXT,
    StartTime     DATETIME      NOT NULL,
    EndTime       DATETIME      NOT NULL,
    StartingPrice DECIMAL(10,2) NOT NULL,
    CurrentPrice  DECIMAL(10,2) NOT NULL,
    NumberOfBids  INT           NOT NULL DEFAULT 0,
    ShippingStatus VARCHAR(50),
    PaymentStatus  VARCHAR(50),
    FOREIGN KEY (SellerID) REFERENCES Users(UserID),

    CONSTRAINT chk_end_after_start CHECK (EndTime > StartTime),
    CONSTRAINT chk_item_prices CHECK (StartingPrice > 0 AND CurrentPrice >= StartingPrice)
);

-- 4. CategoryItems items <-> categories

CREATE TABLE CategoryItems (
    ItemID     INT,
    CategoryID INT,
    PRIMARY KEY (ItemID, CategoryID),
    FOREIGN KEY (ItemID)     REFERENCES Items(ItemID),
    FOREIGN KEY (CategoryID) REFERENCES Categories(CategoryID)
);

-- 5. Bids one row per bid

CREATE TABLE Bids (
    BidID     INT          PRIMARY KEY,
    ItemID    INT          NOT NULL,
    BidderID  INT          NOT NULL,
    BidAmount DECIMAL(10,2) NOT NULL,
    BidTime   DATETIME     NOT NULL,
    FOREIGN KEY (ItemID)    REFERENCES Items(ItemID),
    FOREIGN KEY (BidderID)  REFERENCES Users(UserID),

    CONSTRAINT uq_bid_amount UNIQUE (ItemID, BidAmount), 
    CONSTRAINT uq_bid_time   UNIQUE (ItemID, BidTime) 
);

-- 6. ShippingOptions seller-defined shipping methods

CREATE TABLE ShippingOptions (
    ShippingOptionID    INT          PRIMARY KEY,
    SellerID            INT          NOT NULL,
    ShippingMethod      VARCHAR(100) NOT NULL,
    Price               DECIMAL(10,2) NOT NULL,
    EstimatedDeliveryTime INT,
    FOREIGN KEY (SellerID) REFERENCES Users(UserID),

    CONSTRAINT chk_shipping_price CHECK (Price >= 0),
    CONSTRAINT chk_delivery_time CHECK (EstimatedDeliveryTime > 0)
);

-- 7. Auctions one row per auction

CREATE TABLE Auctions (
    ItemID                     INT          PRIMARY KEY,
    WinningBidderID            INT,
    SelectedShippingOptionID INT,
    PaymentStatus              VARCHAR(50),
    TrackingInformation        VARCHAR(200),
    DeliveryConfirmed          BOOLEAN       NOT NULL DEFAULT FALSE,
    ShipByDate                 DATETIME,
    ActualShipDate             DATETIME,
    FOREIGN KEY (ItemID)                     REFERENCES Items(ItemID),
    FOREIGN KEY (WinningBidderID)            REFERENCES Users(UserID),
    FOREIGN KEY (SelectedShippingOptionID) REFERENCES ShippingOptions(ShippingOptionID)
);

-- 8. BankInfo seller payout details

CREATE TABLE BankInfo (
    UserID        INT          PRIMARY KEY,
    BankName      VARCHAR(100)  NOT NULL,
    RoutingNumber VARCHAR(50)   NOT NULL,
    AccountNumber VARCHAR(50)   NOT NULL,
    FOREIGN KEY (UserID) REFERENCES Users(UserID),
    
    CONSTRAINT chk_routing CHECK (
        LENGTH(RoutingNumber) = 9
        AND LENGTH(TRIM('0123456789' FROM RoutingNumber)) = 0
    )
);

-- 9. CreditCard payment details

CREATE TABLE CreditCard (
    UserID          INT          PRIMARY KEY,
    CardNumber      VARCHAR(20)   NOT NULL,
    ExpirationDate  DATE          NOT NULL,
    CVVCode         VARCHAR(4)    NOT NULL,
    CardholderName  VARCHAR(100)  NOT NULL,
    BillingAddress  VARCHAR(200)  NOT NULL,
    FOREIGN KEY (UserID) REFERENCES Users(UserID),
    CONSTRAINT chk_card_number CHECK (
        LENGTH(CardNumber) BETWEEN 13 AND 19
        AND LENGTH(TRIM('0123456789' FROM CardNumber)) = 0
    ),
    CONSTRAINT chk_cvv CHECK (
        LENGTH(CVVCode) BETWEEN 3 AND 4
        AND LENGTH(TRIM('0123456789' FROM CVVCode)) = 0
    ),
    CONSTRAINT valid_expiration CHECK (ExpirationDate > CURRENT_DATE)
);

-- 10. SellerReviews feedback on seller

CREATE TABLE SellerReviews (
    ReviewID    INT          PRIMARY KEY,
    SellerID    INT          NOT NULL,
    BuyerID     INT          NOT NULL,
    ItemID      INT          NOT NULL,
    Rating      INT          NOT NULL,
    Feedback    TEXT,
    ReviewDate  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (SellerID) REFERENCES Users(UserID),
    FOREIGN KEY (BuyerID)  REFERENCES Users(UserID),
    FOREIGN KEY (ItemID)   REFERENCES Items(ItemID),
    CONSTRAINT chk_rating CHECK (Rating BETWEEN 1 AND 5),
    CONSTRAINT uq_buyer_review UNIQUE (SellerID, BuyerID, ItemID)
);

-- 11. Time clock

CREATE TABLE Time (
    CurrentTime DATETIME NOT NULL
);

-- 12. SystemLogs

CREATE TABLE SystemLogs (
    LogID              INT AUTO_INCREMENT PRIMARY KEY,
    EventType          VARCHAR(50)  NOT NULL,
    EventDescription TEXT,
    RelatedEntityID  INT,
    EntityType         VARCHAR(50),
    CreatedAt          TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UserID             INT,
FOREIGN KEY (UserID) REFERENCES Users(UserID)
);

-- ============================================================
-- Performance Indexes
-- ============================================================

CREATE INDEX idx_seller       ON Items(SellerID);
CREATE INDEX idx_bidder       ON Bids(BidderID);
CREATE INDEX idx_item         ON Bids(ItemID);
CREATE INDEX idx_auction_end   ON Items(EndTime);
CREATE INDEX idx_bid_time      ON Bids(BidTime);
CREATE INDEX idx_item_price    ON Items(CurrentPrice);
CREATE INDEX idx_category_name ON Categories(CategoryName);
CREATE INDEX idx_user_email    ON Users(Email);
CREATE INDEX idx_payment_status ON Auctions(PaymentStatus);
CREATE INDEX idx_shipping_status ON Items(ShippingStatus);

-- ============================================================
-- AuctionBase - Business Logic (Triggers + Stored Procedures)
-- ============================================================
-- T1: Prevent self-bidding

DELIMITER //

CREATE TRIGGER prevent_self_bidding
BEFORE INSERT ON Bids
FOR EACH ROW
BEGIN
    DECLARE v_seller_id INT;
    SELECT SellerID INTO v_seller_id FROM Items WHERE ItemID = NEW.ItemID;
    IF v_seller_id = NEW.BidderID THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Cannot bid on your own item';
    END IF;
END//


-- T2: New bid must be strictly higher than previous bids

CREATE TRIGGER validate_bid_amount
BEFORE INSERT ON Bids
FOR EACH ROW
BEGIN
    DECLARE v_max_bid DECIMAL(10,2);
    SELECT COALESCE(MAX(BidAmount), 0) INTO v_max_bid
    FROM Bids WHERE ItemID = NEW.ItemID;
    IF NEW.BidAmount <= v_max_bid THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Bid must be higher than previous bids';
    END IF;
END//


-- T3: Bid must be within auction window AND match system time

CREATE TRIGGER validate_bid_time
BEFORE INSERT ON Bids
FOR EACH ROW
BEGIN
    DECLARE v_start DATETIME;
    DECLARE v_end   DATETIME;
    DECLARE v_now   DATETIME;
    SELECT StartTime, EndTime INTO v_start, v_end FROM Items WHERE ItemID = NEW.ItemID;
    SELECT CurrentTime INTO v_now FROM Time LIMIT 1;
    IF NEW.BidTime < v_start OR NEW.BidTime > v_end THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Bid time must be within auction period';
    ELSEIF NEW.BidTime != v_now THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Bid time must match current system time';
    END IF;
END//


-- T4: Auto-increment bid count and sync current price

CREATE TRIGGER update_bid_count
AFTER INSERT ON Bids
FOR EACH ROW
BEGIN
    UPDATE Items
    SET NumberOfBids = NumberOfBids + 1,
        CurrentPrice  = NEW.BidAmount
    WHERE ItemID = NEW.ItemID;
    INSERT INTO SystemLogs (EventType, EventDescription, RelatedEntityID, EntityType, UserID)
    VALUES ('NEW_BID', CONCAT('New bid placed: $', NEW.BidAmount), NEW.ItemID, 'BID', NEW.BidderID);
END//


-- T5: System time can only forward

CREATE TRIGGER validate_current_time
BEFORE UPDATE ON Time
FOR EACH ROW
BEGIN
    IF NEW.CurrentTime < OLD.CurrentTime THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'System time cannot move backward';
    END IF;
END//


-- T6: Shipping deadline + tracking enforcement

CREATE TRIGGER enforce_shipping_deadline
BEFORE UPDATE ON Auctions
FOR EACH ROW
BEGIN
    IF NEW.PaymentStatus = 'COMPLETED' AND OLD.PaymentStatus != 'COMPLETED' THEN
        SET NEW.ShipByDate = DATE_ADD(CURRENT_TIMESTAMP, INTERVAL 2 DAY);
        INSERT INTO SystemLogs (EventType, EventDescription, RelatedEntityID, EntityType)
        VALUES ('PAYMENT_COMPLETED', 'Payment completed, shipping deadline set', NEW.ItemID, 'AUCTION');
    END IF;

    IF NEW.TrackingInformation IS NOT NULL AND OLD.TrackingInformation IS NULL THEN
        SET NEW.ActualShipDate = CURRENT_TIMESTAMP;
        IF NEW.ActualShipDate > NEW.ShipByDate THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Shipping deadline exceeded';
        END IF;
        INSERT INTO SystemLogs (EventType, EventDescription, RelatedEntityID, EntityType)
        VALUES ('ITEM_SHIPPED', CONCAT('Item shipped with tracking: ', NEW.TrackingInformation), NEW.ItemID, 'AUCTION');
    END IF;
END//


-- T7: Auto-close auction when system time passes end time

CREATE TRIGGER close_auction
AFTER UPDATE ON Time
FOR EACH ROW
BEGIN
    DECLARE done INT DEFAULT FALSE;
    DECLARE v_item_id INT;
    DECLARE cur CURSOR FOR
        SELECT ItemID FROM Items
        WHERE EndTime <= NEW.CurrentTime
          AND ItemID NOT IN (SELECT ItemID FROM Auctions);
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;

    OPEN cur;
    read_loop: LOOP
        FETCH cur INTO v_item_id;
        IF done THEN LEAVE read_loop; END IF;
        CALL CompleteAuction(v_item_id);
    END LOOP;
    CLOSE cur;
END//

DELIMITER ;


-- Stored Procedures

DELIMITER //

CREATE PROCEDURE CompleteAuction(IN p_ItemID INT)
BEGIN
    DECLARE v_winner INT;
    DECLARE v_amount  DECIMAL(10,2);

    SELECT BidderID, BidAmount INTO v_winner, v_amount
    FROM Bids WHERE ItemID = p_ItemID
    ORDER BY BidAmount DESC, BidTime ASC LIMIT 1;

    INSERT INTO Auctions (ItemID, WinningBidderID, PaymentStatus)
    VALUES (p_ItemID, v_winner, 'PENDING_PAYMENT');

    INSERT INTO SystemLogs (EventType, EventDescription, RelatedEntityID, EntityType)
    VALUES ('AUCTION_COMPLETED', CONCAT('Auction completed, winning bid: $', v_amount), p_ItemID, 'ITEM');
END//

CREATE PROCEDURE ProcessPayment(
    IN p_ItemID INT,
    In p_ShippingOptionID INT
)
BEGIN
    DECLARE v_bid      DECIMAL(10,2);
    DECLARE v_shipping DECIMAL(10,2);

    SELECT CurrentPrice INTO v_bid FROM Items WHERE ItemID = p_ItemID;
    SELECT Price INTO v_shipping FROM ShippingOptions WHERE ShippingOptionID = p_ShippingOptionID;

    UPDATE Auctions
    SET PaymentStatus = 'COMPLETED',
        SelectedShippingOptionID = p_ShippingOptionID
    WHERE ItemID = p_ItemID;

    INSERT INTO SystemLogs (EventType, EventDescription, RelatedEntityID, EntityType)
    VALUES ('PAYMENT_PROCESSED',
            CONCAT('Payment processed: $', v_bid + v_shipping),
            p_ItemID, 'PAYMENT');
END//

CREATE PROCEDURE ShipItem(
    IN p_ItemID INT,
    IN p_TrackingInfo VARCHAR(200)
)
BEGIN
    UPDATE Auctions
    SET TrackingInformation = p_TrackingInfo
    WHERE ItemID = p_ItemID;
END//

CREATE PROCEDURE ConfirmDelivery(IN p_ItemID INT)
BEGIN
    UPDATE Auctions
    SET DeliveryConfirmed = TRUE
    WHERE ItemID = p_ItemID;

    INSERT INTO SystemLogs (EventType, EventDescription, RelatedEntityID, EntityType)
    VALUES ('DELIVERY_CONFIRMED', 'Buyer confirmed delivery', p_ItemID, 'FULFILLMENT');
END//

DELIMITER ;


-- AuctionBase - Reporting Views

CREATE VIEW ActiveAuctions AS
SELECT
    i.ItemID,
    i.ItemName,
    i.CurrentPrice,
    i.NumberOfBids,
    i.EndTime,
    u.Username AS SellerName,
    TIMESTAMPDIFF(MINUTE, CURRENT_TIMESTAMP, i.EndTime) AS MinutesRemaining,
    GROUP_CONCAT(c.CategoryName) AS Categories
FROM Items i
JOIN Users u ON i.SellerID = u.UserID
LEFT JOIN CategoryItems ci ON i.ItemID = ci.ItemID
LEFT JOIN Categories c ON ci.CategoryID = c.CategoryID
WHERE i.EndTime > CURRENT_TIMESTAMP
  AND i.ItemID NOT IN (SELECT ItemID FROM Auctions WHERE PaymentStatus = 'COMPLETED')
GROUP BY i.ItemID, i.ItemName, i.CurrentPrice, i.NumberOfBids, i.EndTime, u.Username;

CREATE VIEW UserRatings AS
SELECT
    sr.SellerID,
    u.Username,
    COUNT(*) AS TotalReviews,
    ROUND(AVG(sr.Rating), 2) AS AverageRating,
    COUNT(CASE WHEN sr.Rating = 5 THEN 1 END) AS FiveStarReviews,
    COUNT(CASE WHEN sr.Rating = 1 THEN 1 END) AS OneStarReviews,
    MAX(sr.ReviewDate) AS LastReviewDate
FROM SellerReviews sr
JOIN Users u ON sr.SellerID = u.UserID
GROUP BY sr.SellerID, u.Username;

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
    a.TrackingInformation,
    a.DeliveryConfirmed,
    so.ShippingMethod,
    so.Price AS ShippingCost
FROM Items i
LEFT JOIN Auctions a ON i.ItemID = a.ItemID
LEFT JOIN Users s ON i.SellerID = s.UserID
LEFT JOIN Users b ON a.WinningBidderID = b.UserID
LEFT JOIN ShippingOptions so ON a.SelectedShippingOptionID = so.ShippingOptionID
WHERE i.EndTime < CURRENT_TIMESTAMP;

CREATE VIEW RecentActivity AS
SELECT 'BID' AS ActivityType, b.BidTime AS ActivityTime,
       i.ItemID, i.ItemName, u.Username, b.BidAmount AS Amount, NULL AS Status
FROM Bids b
JOIN Items i ON b.ItemID = i.ItemID
JOIN Users u ON b.BidderID = u.UserID

UNION ALL

SELECT 'PAYMENT' AS ActivityType, l.CreatedAt AS ActivityTime,
       l.RelatedEntityID AS ItemID, i.ItemName, u.Username,
       i.CurrentPrice AS Amount, a.PaymentStatus AS Status
FROM SystemLogs l
JOIN Items i ON l.RelatedEntityID = i.ItemID
JOIN Auctions a ON i.ItemID = a.ItemID
JOIN Users u ON a.WinningBidderID = u.UserID
WHERE l.EventType = 'PAYMENT_PROCESSED'

UNION ALL

SELECT 'SHIPPING' AS ActivityType, l.CreatedAt AS ActivityTime,
       l.RelatedEntityID AS ItemID, i.ItemName, u.Username,
       NULL AS Amount, a.TrackingInformation AS Status
FROM SystemLogs l
JOIN Items i ON l.RelatedEntityID = i.ItemID
JOIN Users u ON i.SellerID = u.UserID
WHERE l.EventType = 'ITEM_SHIPPED'

ORDER BY ActivityTime DESC
LIMIT 100;

CREATE VIEW UserActivitySummary AS
SELECT
    u.UserID,
    u.Username,
    u.IsSeller,
    u.IsBuyer,
    COUNT(DISTINCT i.ItemID) AS ItemsListed,
    COUNT(DISTINCT b.ItemID) AS ItemsBidOn,
    COUNT(DISTINCT CASE WHEN a.WinningBidderID = u.UserID THEN a.ItemID END) AS AuctionsWon,
    COALESCE(AVG(sr.Rating), 0) AS SellerRating
FROM Users u
LEFT JOIN Items i ON u.UserID = i.SellerID
LEFT JOIN Bids b ON u.UserID = b.BidderID
LEFT JOIN Auctions a ON u.UserID = a.WinningBidderID
LEFT JOIN SellerReviews sr ON u.UserID = sr.SellerID
GROUP BY u.UserID, u.Username, u.IsSeller, u.IsBuyer;

CREATE VIEW ShippingStatusView AS
SELECT
    i.ItemID,
    i.ItemName,
    s.Username AS SellerName,
    b.Username AS BuyerName,
    a.PaymentStatus,
    a.TrackingInformation,
    a.ShipByDate,
    a.ActualShipDate,
    CASE
        WHEN a.ActualShipDate > a.ShipByDate THEN 'LATE'
        WHEN a.ActualShipDate IS NULL AND CURRENT_TIMESTAMP > a.ShipByDate THEN 'OVERDUE'
        ELSE 'ON_TIME'
    END AS ShippingTimeStatus
FROM Items i
JOIN Auctions a ON i.ItemID = a.ItemID
JOIN Users s ON i.SellerID = s.UserID
JOIN Users b ON a.WinningBidderID = b.UserID
WHERE a.PaymentStatus = 'COMPLETED';


-- Seed Data

INSERT INTO Time (CurrentTime) VALUES (NOW());

INSERT INTO Users (UserID, Username, Email, Name, Address, PhoneNumber, IsSeller, IsBuyer, RegistrationDate, LastLoginDate) VALUES
(1, 'marcus_delgado',   'marcus.delgado@example.com',   'Marcus Delgado',    '412 W 74th St, Apt 3B, New York, NY 10024',         '212-555-0142', TRUE,  FALSE, DEFAULT, NULL),
(2, 'dana_whitfield',   'dana.whitfield@example.com',   'Dana Whitfield',    '88 Court St, Apt 12C, Brooklyn, NY 11201',          '718-555-0186', FALSE, TRUE, DEFAULT, NULL),
(3, 'priya_r',          'priya.raghunathan@example.com','Priya Raghunathan', '1525 Lexington Ave, Apt 21, New York, NY 10028',   '646-555-0173', TRUE,  TRUE, DEFAULT, NULL),
(4, 'andre_fontaine',   'andre.fontaine@example.com',    'Andre Fontaine',   '307 Lenox Ave, Apt 4, New York, NY 10027',          '917-555-0159', TRUE,  FALSE, DEFAULT, NULL),
(5, 'renee_castillo',   'renee.castillo@example.com',   'Renee Castillo',    '94-11 63rd Dr, Apt 2A, Flushing, NY 11375',         '347-555-0128', FALSE, TRUE, DEFAULT, NULL),
(6,  'elena_v',      'elena.vasquez@example.com',     'Elena Vasquez',   '2210 86th St, Apt 5, Brooklyn, NY 11214',        '718-555-0134', TRUE, TRUE, '2026-01-12 09:15:00', '2026-09-28 18:40:00'),
(7,  'nathan_kim',   'nathan.kim@example.com',        'Nathan Kim',      '1750 Amsterdam Ave, Apt 8, New York, NY 10032',   '212-555-0167', TRUE, TRUE, '2026-01-19 11:05:00', '2026-09-30 08:22:00'),
(8,  'yusuf_a',      'yusuf.abdallah@example.com',    'Yusuf Abdallah',  '39-12 82nd St, Apt 1, Jackson Heights, NY 11372','347-555-0192', TRUE, TRUE, '2026-02-03 14:30:00', '2026-09-25 20:10:00'),
(9,  'miriam_katz',  'miriam.katz@example.com',       'Miriam Katz',     '640 Riverside Dr, Apt 17C, New York, NY 10024',   '646-555-0119', TRUE, TRUE, '2026-02-14 10:45:00', '2026-09-29 07:55:00'),
(10, 'carlos_mendez','carlos.mendez@example.com',     'Carlos Mendez',   '3120 Steinway St, Astoria, NY 11101',            '929-555-0175', TRUE, TRUE, '2026-03-02 16:20:00', '2026-09-21 21:35:00'),
(11, 'bridget_d',    'bridget.donnelly@example.com',  'Bridget Donnelly','58-14 69th Ave, Apt 3, Ridgewood, NY 11385',    '718-555-0148', TRUE, TRUE, '2026-03-18 09:50:00', '2026-09-27 13:05:00'),
(12, 'sal_romano',   'salvatore.romano@example.com',  'Salvatore Romano','120 Sullivan St, Apt 9A, New York, NY 10012',   '212-555-0121', TRUE, TRUE, '2026-04-07 12:00:00', '2026-09-30 16:15:00'),
(13, 'nadia_rahimi', 'nadia.rahimi@example.com',      'Nadia Rahimi',    '1680 Brighton Ave, Apt 2, Brooklyn, NY 11235',   '347-555-0156', TRUE, TRUE, '2026-04-21 08:35:00', '2026-09-26 10:45:00'),
(14, 'irina_v',      'irina.volkova@example.com',     'Irina Volkova',   '25-31 49th St, Apt 7, Long Island City, NY 11101','929-555-0183', TRUE, TRUE, '2026-05-09 15:25:00', '2026-09-24 19:20:00'),
(15, 'devon_clarke', 'devon.clarke@example.com',      'Devon Clarke',    '4320 Bay Ridge Pkwy, Apt 6, Brooklyn, NY 11228', '718-555-0164', TRUE, TRUE, '2026-05-28 13:10:00', '2026-09-23 22:05:00');

INSERT INTO BankInfo (UserID, BankName, RoutingNumber, AccountNumber) VALUES
(1, 'Chelsea National Bank',    '021000431', 'ACC7301846'),
(3, 'New York Community Bank',  '021000892', 'ACC5629073'),
(4, 'Harlem Community Bank',    '021001376', 'ACC8145239'),
(6,  'Bay Ridge Savings Bank',     '021001905','ACC3094718'),
(7,  'Washington Heights Federal','021002188', 'ACC4460527'),
(8,  'Queensboro Community Bank',  '021002471', 'ACC5823096'),
(9,  'Upper West Side Bank',      '021002764', 'ACC6173480'),
(10, 'Astoria National Bank',      '021003057', 'ACC7751903'),
(11, 'Ridgewood Union Bank',       '021003340', 'ACC9204671'),
(12, 'SoHo Capital Bank',         '021003623', 'ACC2685148'),
(13, 'Brighton Beach Trust',       '021003906', 'ACC4310772'),
(14, 'Long Island City Bank',     '021004189', 'ACC5962315'),
(15, 'Brooklyn Heights Savings',  '021004462', 'ACC7438086');

INSERT INTO CreditCard (UserID, CardNumber, ExpirationDate, CVVCode, CardholderName, BillingAddress) VALUES
(2, '4123456789012349', '2031-03-31', '214',  'Dana Whitfield',   '88 Court St, Apt 12C, Brooklyn, NY 11201'),
(3, '5212345678901236', '2030-07-31', '583',  'Priya Raghunathan','1525 Lexington Ave, Apt 21, New York, NY 10028'),
(5, '372345678901230',  '2029-11-30', '9074', 'Renee Castillo',   '94-11 63rd Dr, Apt 2A, Flushing, NY 11375');

INSERT INTO Categories (CategoryID, CategoryName, CategoryDescription) VALUES
(1, 'Electronics',         'Phones, laptops, and gadgets'),
(2, 'Collectibles',        'Rare items and memorabilia'),
(3, 'Home & Garden',       'Furniture and decor'),
(4, 'Books',               'New and used books'),
(5,  'Sports Memorabilia', 'Trading cards, autographs, and match memorabilia'),
(6,  'Furniture',          'Antique and modern furniture'),
(7,  'Jewelry',            'Rings, watches, and fine jewelry'),
(8,  'Musical Instruments','Guitars, drums, and studio gear'),
(9,  'Tools & Hardware',   'Power tools, hand tools, and workshop equipment'),
(10, 'Art & Prints',       'Original art, prints, and sculpture'),
(11, 'Vintage Clothing',   'Designer and retro apparel'),
(12, 'Automotive Parts',   'Restoration parts and accessories'),
(13, 'Baby & Nursery',     'Furniture, clothing, and gear for infants'),
(14, 'Outdoor & Camping',  'Tents, gear, and outdoor equipment');

INSERT INTO Items (
    ItemID, ItemName, SellerID, Location, Country, Description,
    StartTime, EndTime, StartingPrice, CurrentPrice, NumberOfBids
) VALUES
(101, 'Vintage Typewriter', 1, 'Upper West Side, New York, USA', 'USA',
    'Well-preserved 1940s typewriter in working condition.',
    NOW(), DATE_ADD(NOW(), INTERVAL 7 DAY), 50.00, 50.00, 0),
(102, 'Wireless Headphones', 3, 'Midtown East, New York, USA', 'USA',
    'Noise-cancelling over-ear headphones, mint condition.',
    NOW(), DATE_ADD(NOW(), INTERVAL 5 DAY), 120.00, 120.00, 0),
(103, 'Antique Clock', 4, 'Harlem, New York, USA', 'USA',
    'Grandfather clock, mahogany finish.',
    DATE_ADD(NOW(), INTERVAL 2 DAY), DATE_ADD(NOW(), INTERVAL 3 DAY), 200.00, 200.00, 0),
(104, 'Signed Baseball Bat', 6, 'Bay Ridge, Brooklyn, USA', 'USA',
    'Babe Ruth replica bat with certificate of authenticity.',
    NOW(), DATE_ADD(NOW(), INTERVAL 7 DAY), 150.00, 150.00, 0),
(105, 'Oil Painting Harbor Sunset', 7, 'Washington Heights, New York, USA', 'USA',
    'Acrylic seascape on 24x36 inch canvas, framed and ready to hang.',
    NOW(), DATE_ADD(NOW(), INTERVAL 5 DAY), 320.00, 320.00, 0),
(106, 'Cordless Drill Set', 8, 'Jackson Heights, Queens, USA', 'USA',
    '20V cordless drill with two batteries, charger, and hard case.',
    NOW(), DATE_ADD(NOW(), INTERVAL 4 DAY), 75.00, 75.00, 0),
(107, 'Vintage Baby Grand Piano', 9, 'Upper West Side, New York, USA', 'USA',
    'Restored 1920s baby grand piano with bench and new hammers.',
    NOW(), DATE_ADD(NOW(), INTERVAL 14 DAY), 2500.00, 2500.00, 0),
(108, 'Electric Guitar Blues Spec', 10, 'Astoria, Queens, USA', 'USA',
    'Custom shop electric guitar, hard case and amp included.',
    NOW(), DATE_ADD(NOW(), INTERVAL 6 DAY), 850.00, 850.00, 0),
(109, 'Antique Persian Rug', 11, 'Ridgewood, Queens, USA', 'USA',
    'Hand-knotted wool rug, 9 by 12 feet, original fringe, no repairs.',
    NOW(), DATE_ADD(NOW(), INTERVAL 9 DAY), 640.00, 640.00, 0),
(110, 'Diamond Engagement Ring', 12, 'SoHo, New York, USA', 'USA',
    '1.5 carat ring, GIA certified, size 6, white gold band.',
    NOW(), DATE_ADD(NOW(), INTERVAL 10 DAY), 4200.00, 4200.00, 0),
(111, 'Restored 1968 Mustang Engine', 13, 'Brighton Beach, Brooklyn, USA', 'USA',
    'Rebuilt 289 cubic inch V8 with original paperwork and stand.',
    NOW(), DATE_ADD(NOW(), INTERVAL 12 DAY), 1850.00, 1850.00, 0),
(112, 'Vintage Quilted Handbag', 14, 'Long Island City, Queens, USA', 'USA',
    'Classic quilted leather shoulder bag from the 1990s, excellent condition.',
    NOW(), DATE_ADD(NOW(), INTERVAL 8 DAY), 950.00, 950.00, 0),
(113, 'Four Person Camping Tent', 15, 'Bay Ridge, Brooklyn, USA', 'USA',
    'Waterproof four-person tent with footprint, used twice.',
    NOW(), DATE_ADD(NOW(), INTERVAL 3 DAY), 110.00, 110.00, 0);

INSERT INTO CategoryItems (ItemID, CategoryID) VALUES
(101, 2), (101, 4),
(102, 1),
(103, 2), (103, 3),
(104, 5),  
(105, 10),  
(106, 9),   
(107, 6), 
(108, 8), 
(109, 3),   
(110, 7),  
(111, 12), 
(112, 11),  
(113, 14); 

INSERT INTO ShippingOptions (ShippingOptionID, SellerID, ShippingMethod, Price, EstimatedDeliveryTime) VALUES
(1001, 1, 'Standard Mail',    5.00,  7),
(1002, 1, 'Express Courier',  25.00, 2),
(1003, 3, 'Standard Mail',    6.00,  6),
(1004, 3, 'Express Courier',  30.00, 1),
(1005, 4, 'Local Pickup',     0.00,  1),
(1006, 4, 'Expedited Shipping', 20.00, 3),
(1007, 6,  'Standard Mail',     6.50,  6),
(1008, 7,  'White Glove Delivery', 95.00, 4),
(1009, 8,  'Standard Mail',     7.00,  5),
(1010, 9,  'Freight Shipping',  250.00, 10),
(1011, 10, 'Insured Express',   45.00,  2),
(1012, 11, 'Standard Mail',     8.00,  7),
(1013, 12, 'Secure Delivery',   30.00,  2),
(1014, 13, 'Heavy Freight',     180.00, 8),
(1015, 14, 'Standard Mail',     5.50,  6),
(1016, 15, 'Expedited Shipping', 18.00, 3);

INSERT INTO Bids (BidID, ItemID, BidderID, BidAmount, BidTime) VALUES
(1, 101, 2,  55.00, NOW()),
(2, 101, 5,  60.00, NOW()),
(3, 102, 2, 125.00, NOW()),
(4, 103, 3, 210.00, NOW()),
(5, 103, 5, 225.00, NOW()),
(6,  104, 2,  165.00, NOW()),
(7,  105, 5,  350.00, NOW()),
(8,  106, 3,   85.00, NOW()),
(9,  107, 11, 2700.00, NOW()),
(10, 108, 4,  900.00, NOW()),
(11, 109, 12, 690.00, NOW()),
(12, 110, 8, 4500.00, NOW()),
(13, 111, 14, 1950.00, NOW()),
(14, 112, 6, 1000.00, NOW()),
(15, 113, 7,  125.00, NOW());

UPDATE Items 
SET EndTime = DATE_SUB(NOW(), INTERVAL 1 HOUR), 
    CurrentPrice = StartingPrice + 25.00, 
    NumberOfBids = 1
WHERE ItemID = 113;

INSERT INTO Auctions (
    ItemID, WinningBidderID, SelectedShippingOptionID,
    PaymentStatus, TrackingInformation, DeliveryConfirmed,
    ShipByDate, ActualShipDate
) VALUES (
    113, 7, 1012, 'COMPLETED', 'TRK0113', TRUE,
    NOW(), DATE_SUB(NOW(), INTERVAL 1 HOUR)
);

INSERT INTO SellerReviews (ReviewID, SellerID, BuyerID, ItemID, Rating, Feedback, ReviewDate) VALUES
(1, 1, 2, 101, 5, 'Great communication, item as described!', NOW()),
(2, 4, 5, 103, 4, 'Item arrived on time, well packed.', NOW()),
(3, 3, 2, 102, 5, 'Excellent quality headphones.', NOW()),
(4,  6,  2,  104, 5, 'Fast shipping and the certificate was exactly as promised.', '2026-09-20 12:30:00'),
(5,  7,  5,  105, 5, 'White glove delivery was careful and the painting is stunning.', '2026-09-21 16:45:00'),
(6,  8,  3,  106, 4, 'Drill works great, battery charged fine on arrival.',         '2026-09-22 09:10:00'),
(7,  9,  11, 107, 5, 'Piano was tuned before delivery, seller answered every question.', '2026-09-18 14:20:00'),
(8,  10, 4,  108, 5, 'Guitar sounds incredible, packaging was professional.',      '2026-09-19 10:05:00'),
(9,  11, 12, 109, 4, 'Rug arrived folded, no damage, colors match the photos.',    '2026-09-17 18:55:00'),
(10, 12, 8,  110, 5, 'Ring is certified and exactly as described. Highly recommended.', '2026-09-23 11:35:00'),
(11, 13, 14, 111, 4, 'Engine runs strong, paperwork made the rebuild easy to verify.', '2026-09-16 20:15:00'),
(12, 14, 6,  112, 4, 'Beautiful bag, strap was in great shape for its age.',        '2026-09-15 13:00:00'),
(13, 15, 7,  113, 5, 'Tent was spotless and shipped the next morning.',            '2026-09-24 08:25:00');

INSERT INTO SystemLogs (EventType, EventDescription, RelatedEntityID, EntityType, UserID) VALUES
('NEW_BID',        'New bid placed: $60.00',     101, 'BID', 5),
('PAYMENT_PROCESSED', 'Payment processed: $225.00', 103, 'PAYMENT', 5),
('ITEM_SHIPPED',   'Item shipped with tracking TRK1003', 103, 'AUCTION', 4),
('DELIVERY_CONFIRMED', 'Buyer confirmed delivery', 103, 'FULFILLMENT', 5),
('USER_REGISTERED',     'New seller and buyer registered: elena_v',         NULL,   'USER',     6,  '2026-01-12 09:15:00'),
('USER_REGISTERED',     'New seller and buyer registered: devon_clarke',  NULL,   'USER',     15, '2026-05-28 13:10:00'),
('CATEGORY_ADDED',      'Category added: Outdoor & Camping',              NULL,   'CATEGORY', 6,  '2026-06-01 10:00:00'),
('ITEM_LISTED',         'Item listed: Signed Baseball Bat',                104,   'ITEM',     6,  '2026-09-01 09:30:00'),
('ITEM_LISTED',         'Item listed: Diamond Engagement Ring',            110,   'ITEM',     12, '2026-09-02 15:45:00'),
('ITEM_LISTED',         'Item listed: Vintage Baby Grand Piano',           107,   'ITEM',     9,  '2026-09-03 11:20:00'),
('AUCTION_COMPLETED',   'Auction completed, winning bid: $165.00',         104,   'ITEM',     2,  '2026-09-08 18:00:00'),
('AUCTION_COMPLETED',   'Auction completed, winning bid: $4500.00',        110,   'ITEM',     8,  '2026-09-12 12:00:00'),
('PAYMENT_COMPLETED',   'Payment received for item 105',                    105,   'AUCTION',  5,  '2026-09-21 16:40:00'),
('SELLER_REVIEW_ADDED', 'Review posters for item 109 (rating 4)',          109,   'REVIEW',   12, '2026-09-17 19:00:00');