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
  EXPIRY_DATETIME     TIMESTAMP_NTZ,              -- NULL = current
  IS_CURRENT          BOOLEAN         DEFAULT TRUE,
  HASHDIFF            NUMBER          NOT NULL,   -- hash of tracked attrs

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
-- Load today's file(s) into STAGING.EMPL_SNAPSHOT (COPY INTO, external stage, etc.)

-- Why HASHDIFF?
-- A single numeric hash of all tracked attributes lets you detect changes in one comparison—fast, stable, and null‑safe when built from a null‑preserving object.

CREATE OR REPLACE PROCEDURE EMP.TARGET.PROC_EMPL_SCD2_FROM_SNAPSHOT(p_src_table STRING)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
DECLARE
    cur_ts          TIMESTAMP := CURRENT_TIMESTAMP();
    rows_expired    NUMBER;
    rows_inserted   NUMBER;
    rows_softclosed NUMBER;
BEGIN
    ------------------------------------------------------------------
    -- 0) Build a null-preserving HASHDIFF for today's snapshot
    ------------------------------------------------------------------
    CREATE OR REPLACE TEMP TABLE _SRC AS
    SELECT
      EMP_ID,
      EMP_NAME,
      DATE_OF_BIRTH,
      EMAIL_ID,
      PHONE_NUMBER,
      SALARY,
      DEPARTMENT,
      WORK_LOCATION,
      HASH(
        TO_VARIANT(
          OBJECT_CONSTRUCT_KEEP_NULL(
            'EMP_NAME',      EMP_NAME,
            'DATE_OF_BIRTH', DATE_OF_BIRTH,
            'EMAIL_ID',      EMAIL_ID,
            'PHONE_NUMBER',  PHONE_NUMBER,
            'SALARY',        SALARY,
            'DEPARTMENT',    DEPARTMENT,
            'WORK_LOCATION', WORK_LOCATION
          )
        )
      ) AS SRC_HASH
    FROM IDENTIFIER(:p_src_table);

    ------------------------------------------------------------------
    -- 1) EXPIRE current rows that have CHANGED (hash changed)
    ------------------------------------------------------------------
    UPDATE TARGET.EMPL_SCD2 T
    SET
      EXPIRY_DATETIME = :cur_ts,
      IS_CURRENT      = FALSE
    FROM _SRC S
    WHERE T.EMP_ID = S.EMP_ID
      AND T.IS_CURRENT = TRUE
      AND NVL(T.HASHDIFF, -1) <> S.SRC_HASH;

    -- GET DIAGNOSTICS rows_expired = ROW_COUNT;

    ------------------------------------------------------------------
    -- 2) INSERT new current rows for NEW keys and CHANGED keys
    ------------------------------------------------------------------
    INSERT INTO TARGET.EMPL_SCD2
    (
      EMP_ID, EMP_NAME, DATE_OF_BIRTH, EMAIL_ID, PHONE_NUMBER,
      SALARY, DEPARTMENT, WORK_LOCATION,
      EFFECTIVE_DATETIME, EXPIRY_DATETIME, IS_CURRENT, HASHDIFF
    )
    SELECT
      S.EMP_ID, S.EMP_NAME, S.DATE_OF_BIRTH, S.EMAIL_ID, S.PHONE_NUMBER,
      S.SALARY, S.DEPARTMENT, S.WORK_LOCATION,
      :cur_ts, NULL, TRUE, S.SRC_HASH
    FROM _SRC S
    LEFT JOIN TARGET.EMPL_SCD2 T
           ON  T.EMP_ID = S.EMP_ID
           AND T.IS_CURRENT = TRUE
    WHERE T.EMP_ID IS NULL                  -- brand-new key
       OR NVL(T.HASHDIFF, -1) <> S.SRC_HASH -- changed attributes
    ;

    -- GET DIAGNOSTICS rows_inserted = ROW_COUNT;

    ------------------------------------------------------------------
    -- 3) OPTIONAL: Soft close keys that disappeared from the snapshot
    --    (treat missing rows as deletions in source)
    ------------------------------------------------------------------
    UPDATE TARGET.EMPL_SCD2 T
    SET
      EXPIRY_DATETIME = :cur_ts,
      IS_CURRENT      = FALSE
    WHERE T.IS_CURRENT = TRUE
      AND NOT EXISTS (
        SELECT 1 FROM _SRC S WHERE S.EMP_ID = T.EMP_ID
      );

    -- GET DIAGNOSTICS rows_softclosed = ROW_COUNT;

    RETURN 'SCD2 via HASH completed at '
           || TO_VARCHAR(:cur_ts, 'YYYY-MM-DD HH24:MI:SS.FF3')
           || ' | expired=' || rows_expired
           || ' | inserted=' || rows_inserted
           || ' | soft_closed=' || rows_softclosed;
END;
;



INSERT INTO STAGING.EMPL_SNAPSHOT VALUES
(1, 'Rahul Sharma', '1986-04-15', 'rahul.sharma@gmail.com','9988776655', 92000, 'Administration', 'Bangalore'),
(2, 'Renuka Devi', '1993-10-19', 'renuka1993@yahoo.com','+91 9911882255', 61000, 'Sales', 'Hyderabad'),
(3, 'Kamalesh', '1991-02-08', 'kamal91@outlook.com','9182736450', 59000, 'Sales', 'Chennai'),
(4, 'Arun Kumar', '1989-05-20', 'arun_kumar@gmail.com','901-287-3465', 74500, 'IT', 'Bangalore');


-- After loading today's full snapshot into STAGING.EMPL_SNAPSHOT
CALL EMP.TARGET.PROC_EMPL_SCD2_FROM_SNAPSHOT('STAGING.EMPL_SNAPSHOT');


select * from TARGET.EMPL_SCD2;
-- EMP_ID,EMP_NAME,DATE_OF_BIRTH,EMAIL_ID,PHONE_NUMBER,SALARY,DEPARTMENT,WORK_LOCATION,EFFECTIVE_DATETIME,EXPIRY_DATETIME,IS_CURRENT,HASHDIFF
-- 1,Rahul Sharma,1986-04-15,rahul.sharma@gmail.com,9988776655,92000.00,Administration,Bangalore,2026-02-03 05:25:27.644,,true,8244892856102733971
-- 2,Renuka Devi,1993-10-19,renuka1993@yahoo.com,+91 9911882255,61000.00,Sales,Hyderabad,2026-02-03 05:25:27.644,,true,2905800558323241295
-- 3,Kamalesh,1991-02-08,kamal91@outlook.com,9182736450,59000.00,Sales,Chennai,2026-02-03 05:25:27.644,,true,7309808551103243070
-- 4,Arun Kumar,1989-05-20,arun_kumar@gmail.com,901-287-3465,74500.00,IT,Bangalore,2026-02-03 05:25:27.644,,true,-7277612797210674328

-- (optional) cleanup after success
TRUNCATE TABLE STAGING.EMPL_SNAPSHOT;  -- safe


INSERT INTO STAGING.EMPL_SNAPSHOT VALUES
(1, 'Rahul Sharma', '1986-04-15', 'rahul.sharma@gmail.com','9988776655', 92000, 'Administration', 'Pune'); --Update city from banglore to Pune

INSERT INTO STAGING.EMPL_SNAPSHOT VALUES
(6, 'Venkatesh D', '1992-01-27', 'dvenkat92@gmail.com', '8921764305', 63500, 'IT', 'Chennai');

select * from STAGING.EMPL_SNAPSHOT;  


-- After loading today's full snapshot into STAGING.EMPL_SNAPSHOT
CALL EMP.TARGET.PROC_EMPL_SCD2_FROM_SNAPSHOT('STAGING.EMPL_SNAPSHOT');

select * from TARGET.EMPL_SCD2 order by 1;

-- truncate TARGET.EMPL_SCD2 

INSERT INTO STAGING.EMPL_SNAPSHOT VALUES
(1, 'Rahul Sharma', '1986-04-15', 'rahul.sharma@gmail.com','9988776655', 92000, 'Administration', 'Banglore'); --Update city again to banglore from Pune


select * from STAGING.EMPL_SNAPSHOT;  
-- After loading today's full snapshot into STAGING.EMPL_SNAPSHOT
CALL EMP.TARGET.PROC_EMPL_SCD2_FROM_SNAPSHOT('STAGING.EMPL_SNAPSHOT');



select * from TARGET.EMPL_SCD2 order by 1;

-- EMP_ID,EMP_NAME,DATE_OF_BIRTH,EMAIL_ID,PHONE_NUMBER,SALARY,DEPARTMENT,WORK_LOCATION,EFFECTIVE_DATETIME,EXPIRY_DATETIME,IS_CURRENT,HASHDIFF
-- 1,Rahul Sharma,1986-04-15,rahul.sharma@gmail.com,9988776655,92000.00,Administration,Bangalore,2026-02-03 05:31:56.832,2026-02-03 05:32:48.685,false,8244892856102733971
-- 1,Rahul Sharma,1986-04-15,rahul.sharma@gmail.com,9988776655,92000.00,Administration,Pune,2026-02-03 05:32:48.685,2026-02-03 05:35:45.205,false,2565575919217753038
-- 1,Rahul Sharma,1986-04-15,rahul.sharma@gmail.com,9988776655,92000.00,Administration,Banglore,2026-02-03 05:35:45.205,,true,6872104618384992967
-- 2,Renuka Devi,1993-10-19,renuka1993@yahoo.com,+91 9911882255,61000.00,Sales,Hyderabad,2026-02-03 05:31:56.832,2026-02-03 05:32:48.685,false,2905800558323241295
-- 3,Kamalesh,1991-02-08,kamal91@outlook.com,9182736450,59000.00,Sales,Chennai,2026-02-03 05:31:56.832,2026-02-03 05:32:48.685,false,7309808551103243070
-- 4,Arun Kumar,1989-05-20,arun_kumar@gmail.com,901-287-3465,74500.00,IT,Bangalore,2026-02-03 05:31:56.832,2026-02-03 05:32:48.685,false,-7277612797210674328
-- 6,Venkatesh D,1992-01-27,dvenkat92@gmail.com,8921764305,63500.00,IT,Chennai,2026-02-03 05:32:48.685,2026-02-03 05:34:29.826,false,-8781167171865622038
