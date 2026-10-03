-- Auction Completion Procedure

CREATE PROCEDURE CompleteAuction(IN p_ItemID INT)
BEGIN
    DECLARE v_WinningBidderID INT;
    DECLARE v_HighestBid DECIMAL(10,2);
    
    IF EXISTS (SELECT 1 FROM Auctions WHERE ItemID = p_ItemID) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Auction is already completed';
    END IF;

    SELECT BidderID, BidAmount INTO v_WinningBidderID, v_HighestBid
    FROM Bids 
    WHERE ItemID = p_ItemID 
    ORDER BY BidAmount DESC 
    LIMIT 1;

    INSERT INTO Auctions (ItemID, WinningBidderID, PaymentStatus)
    VALUES (p_ItemID, v_WinningBidderID, 'PENDING_PAYMENT');

    INSERT INTO SystemLogs (EventType, EventDescription, RelatedEntityID, EntityType)
    VALUES ('AUCTION_COMPLETED', 
            CONCAT('Auction completed with winning bid: $', COALESCE(v_HighestBid, 0)),
            p_ItemID, 
            'ITEM');
END;

-- Payment Processing

CREATE PROCEDURE ProcessPayment(IN p_ItemID INT, IN p_ShippingOptionID INT)
BEGIN
    DECLARE v_Amount DECIMAL(10,2);
    DECLARE v_ShippingCost DECIMAL(10,2);

    SELECT CurrentPrice INTO v_Amount FROM Items WHERE ItemID = p_ItemID;
    SELECT Price INTO v_ShippingCost FROM ShippingOptions WHERE ShippingOptionID = p_ShippingOptionID;

    UPDATE Auctions 
    SET PaymentStatus = 'COMPLETED',
        SelectedShippingOptionID = p_ShippingOptionID
    WHERE ItemID = p_ItemID;

    IF ROW_COUNT() = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Invalid item ID or auction record missing';
    END IF;

    INSERT INTO SystemLogs (EventType, EventDescription, RelatedEntityID, EntityType)
    VALUES ('PAYMENT_PROCESSED', 
            CONCAT('Payment processed: $', v_Amount + v_ShippingCost),
            p_ItemID,
            'PAYMENT');
END;

-- Update Shipping Status Procedure

CREATE PROCEDURE UpdateShippingStatus(
    IN p_ItemID INT,
    IN p_TrackingInfo VARCHAR(200),
    IN p_Status VARCHAR(50)
)
BEGIN
    UPDATE Items
    SET ShippingStatus = p_Status
    WHERE ItemID = p_ItemID;

    UPDATE Auctions
    SET TrackingInformation = p_TrackingInfo
    WHERE ItemID = p_ItemID;

    INSERT INTO SystemLogs (EventType, EventDescription, RelatedEntityID, EntityType)
    VALUES ('SHIPPING_UPDATE', 
            CONCAT('Shipping status updated to: ', p_Status),
            p_ItemID,
            'SHIPPING');
END;