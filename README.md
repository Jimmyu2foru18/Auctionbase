# AuctionBase

AuctionBase is a relational database management system designed to support an online auction platform. The project models the core operational data required to handle user accounts, item listings, competitive bidding, and final transaction settlement.

<img src="./Auctionbase%20diagram.png" width="550" height="750">

## System Architecture

The database schema is structured around four primary entities that capture the complete lifecycle of an online auction:

* **Users**: Stores participant account information, including unique usernames, contact emails, and registration timestamps. Users can operate as sellers, bidders, or both.
* **Items**: Represents goods listed for auction. Each record tracks listing details, descriptions, financial baselines such as starting prices and reserve prices, active scheduling windows, and current operational status.
* **Bids**: Captures transactional bidding activity. Every record ties a specific user to an item with a monetary offer and a precise timestamp, establishing the chronological history of competition for a listing.
* **CompletedAuctions**: Records the outcome of finalized sales. When an auction closes, this entity maps the winning user, final execution price, and completion timestamp to the corresponding item.

## Programmability and Logic Layer

Database logic is encapsulated through views and stored procedures to enforce data integrity and business rules directly at the database level:

* **Views**: Provide aggregated abstractions over raw tables, exposing real-time summaries of active auction standings, highest current bids, total bid counts, and historical sales reports.
* **Stored Procedures**: Implement transactional control routines for complex workflows. These handle concurrency checks, validation rules preventing sellers from bidding on their own items, minimum bid increments, reserve price evaluations, and auction closure processing.

## Setup Requirements

The system requires PostgreSQL version 15 or newer to support modern identity columns, check constraints, and procedural logic blocks. Deployment follows a strict execution order, starting with the core schema definition, followed by sample data insertion, and concluding with the deployment of views and stored procedures.
