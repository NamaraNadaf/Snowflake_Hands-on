-- SCD2 dimension table (permanent)
use database DB_DA_N01; 
CREATE SCHEMA IF NOT EXISTS STAGING;
CREATE SCHEMA IF NOT EXISTS TARGET;
CREATE OR REPLACE TABLE TARGET.EMPL_SCD2 (
  EMP_ID              NUMBER          NOT NULL,   -- business key
  EMP_NAME            STRING,
  DATE_OF_BIRTH       DATE,
  EMAIL_ID            STRING,
  PHONE_NUMBER        STRING,
  SALARY              NUMBER(18,2),
  DEPARTMENT          STRING,
  WORK_LOCATION       STRING,

  EFFECTIVE_DATETIME  TIMESTAMP_NTZ   NOT NULL,
  EXPIRY_DATETIME     TIMESTAMP_NTZ  ,           -- NULL = current
  -- IS_CURRENT          BOOLEAN         DEFAULT TRUE,
  -- HASHDIFF            NUMBER          NOT NULL,   -- hash of tracked attrs

  CONSTRAINT PK_EMPL_SCD2 PRIMARY KEY (EMP_ID, EFFECTIVE_DATETIME)
);

-- One-run snapshot holder (drop/truncate after the load is applied)
CREATE OR REPLACE TRANSIENT TABLE STAGING.EMPL_SNAPSHOT (
  EMP_ID        NUMBER,
  EMP_NAME      STRING,
  DATE_OF_BIRTH DATE,
  EMAIL_ID      STRING,
  PHONE_NUMBER  STRING,
  SALARY        NUMBER(18,2),
  DEPARTMENT    STRING,
  WORK_LOCATION STRING
);

CREATE OR REPLACE STREAM STAGING.STREAM_EMPL_SCD2 ON TABLE STAGING.EMPL_SNAPSHOT;

-- Load today's file(s) into STAGING.EMPL_SNAPSHOT (COPY INTO, external stage, etc.)

-- Why HASHDIFF?
-- A single numeric hash of all tracked attributes lets you detect changes in one comparison—fast, stable, and null‑safe when built from a null‑preserving object.

CREATE OR REPLACE PROCEDURE DB_DA_N01.TARGET.PROC_EMPL_SCD2_FROM_SNAPSHOT()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
DECLARE
    cur_ts          TIMESTAMP := CURRENT_TIMESTAMP();
BEGIN
    -- Step 0: Capture stream data before it's consumed
    CREATE OR REPLACE TEMPORARY TABLE STAGING.STREAM_CAPTURE AS
    SELECT * FROM STAGING.STREAM_EMPL_SCD2;

    -- Step 1: Expire old records (for DELETEs and UPDATE-deletes)
    MERGE INTO TARGET.EMPL_SCD2 TGT
    USING (
        SELECT * FROM STAGING.STREAM_CAPTURE 
        WHERE METADATA$ACTION = 'DELETE'
    ) STR
    ON TGT.EMP_ID = STR.EMP_ID
       AND TGT.EXPIRY_DATETIME IS NULL
    WHEN MATCHED THEN
        UPDATE SET TGT.EXPIRY_DATETIME = :cur_ts;

    -- Step 2: Insert new records (for INSERTs and UPDATE-inserts)
    INSERT INTO TARGET.EMPL_SCD2 
        (EMP_ID, EMP_NAME, DATE_OF_BIRTH, EMAIL_ID, PHONE_NUMBER, 
         SALARY, DEPARTMENT, WORK_LOCATION, EFFECTIVE_DATETIME, EXPIRY_DATETIME)
    SELECT 
        EMP_ID, EMP_NAME, DATE_OF_BIRTH, EMAIL_ID, PHONE_NUMBER,
        SALARY, DEPARTMENT, WORK_LOCATION, :cur_ts, NULL
    FROM STAGING.STREAM_CAPTURE
    WHERE METADATA$ACTION = 'INSERT';

    DROP TABLE STAGING.STREAM_CAPTURE;
    RETURN 'SCD2 load completed';
END;

TRUNCATE STAGING.EMPL_SNAPSHOT;
INSERT INTO STAGING.EMPL_SNAPSHOT VALUES
(1, 'Rahul Sharma', '1986-04-15', 'rahul.sharma@gmail.com','9988776655', 92000, 'Administration', 'Bangalore'),
(2, 'Renuka Devi', '1993-10-19', 'renuka1993@yahoo.com','+91 9911882255', 61000, 'Sales', 'Hyderabad'),
(3, 'Kamalesh', '1991-02-08', 'kamal91@outlook.com','9182736450', 59000, 'Sales', 'Chennai'),
(4, 'Arun Kumar', '1989-05-20', 'arun_kumar@gmail.com','901-287-3465', 74500, 'IT', 'Bangalore');

select * from STAGING.EMPL_SNAPSHOT;

select * from STAGING.STREAM_EMPL_SCD2;
-- After loading today's full snapshot into STAGING.EMPL_SNAPSHOT
CALL DB_DA_N01.TARGET.PROC_EMPL_SCD2_FROM_SNAPSHOT();


select * from TARGET.EMPL_SCD2;
-- EMP_ID,EMP_NAME,DATE_OF_BIRTH,EMAIL_ID,PHONE_NUMBER,SALARY,DEPARTMENT,WORK_LOCATION,EFFECTIVE_DATETIME,EXPIRY_DATETIME,IS_CURRENT,HASHDIFF
-- 1,Rahul Sharma,1986-04-15,rahul.sharma@gmail.com,9988776655,92000.00,Administration,Bangalore,2026-02-03 05:25:27.644,,true,8244892856102733971
-- 2,Renuka Devi,1993-10-19,renuka1993@yahoo.com,+91 9911882255,61000.00,Sales,Hyderabad,2026-02-03 05:25:27.644,,true,2905800558323241295
-- 3,Kamalesh,1991-02-08,kamal91@outlook.com,9182736450,59000.00,Sales,Chennai,2026-02-03 05:25:27.644,,true,7309808551103243070
-- 4,Arun Kumar,1989-05-20,arun_kumar@gmail.com,901-287-3465,74500.00,IT,Bangalore,2026-02-03 05:25:27.644,,true,-7277612797210674328

-- (optional) cleanup after success
TRUNCATE TABLE STAGING.EMPL_SNAPSHOT;  -- safe


update STAGING.EMPL_SNAPSHOT
set work_location= 'Pune'
where emp_id=1; --Update city from banglore to Pune

INSERT INTO STAGING.EMPL_SNAPSHOT VALUES
(6, 'Venkatesh D', '1992-01-27', 'dvenkat92@gmail.com', '8921764305', 63500, 'IT', 'Chennai');

select * from STAGING.EMPL_SNAPSHOT;  


-- After loading today's full snapshot into STAGING.EMPL_SNAPSHOT
CALL DB_DA_N01.TARGET.PROC_EMPL_SCD2_FROM_SNAPSHOT('STAGING.EMPL_SNAPSHOT');

select * from TARGET.EMPL_SCD2 order by 1;

-- truncate TARGET.EMPL_SCD2 

INSERT INTO STAGING.EMPL_SNAPSHOT VALUES
(1, 'Rahul Sharma', '1986-04-15', 'rahul.sharma@gmail.com','9988776655', 92000, 'Administration', 'Banglore'); --Update city again to banglore from Pune


select * from STAGING.EMPL_SNAPSHOT;  
-- After loading today's full snapshot into STAGING.EMPL_SNAPSHOT
CALL DB_DA_N01.TARGET.PROC_EMPL_SCD2_FROM_SNAPSHOT('STAGING.EMPL_SNAPSHOT');



select * from TARGET.EMPL_SCD2 order by 1;

