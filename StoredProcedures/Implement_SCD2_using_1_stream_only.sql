CREATE OR REPLACE PROCEDURE EMP.TARGET.PROC_EMPL_SCD_TYPE2_Only_1_stream()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
DECLARE
    cur_ts TIMESTAMP := CURRENT_TIMESTAMP();
BEGIN

    -------------------------------------------------------------------
    -- STEP 1: EXPIRE CURRENT ROW FOR TRUE-UPDATES (DELETE in STREAM)
    -------------------------------------------------------------------
    MERGE INTO TARGET.EMPL_SCD2 T
    USING (
        SELECT 
            EID      AS eid,
            METADATA$ACTION   AS action,
            METADATA$ISUPDATE AS isupdate
        FROM STAGING.STREAM_STG_EMPL
        WHERE METADATA$ACTION = 'DELETE'
          AND METADATA$ISUPDATE = TRUE      -- marks UPDATE-pair
    ) S
    ON T.EMP_ID = S.eid
    AND T.EXPIRY_DATETIME IS NULL
    WHEN MATCHED THEN
        UPDATE SET 
            T.EXPIRY_DATETIME = :cur_ts
    ;

    -------------------------------------------------------------------
    -- STEP 2: INSERT NEW VERSION FOR INSERT RECORDS
    --  (new rows + updated rows new image)
    -------------------------------------------------------------------
   INSERT INTO TARGET.EMPL_SCD2
	(emp_id, emp_name, date_of_birth, email_id, phone_number, salary, department, work_location, effective_datetime, expiry_datetime)
	SELECT eid, ename, dob, mail, phone, S.salary, dept, loc, :cur_ts, null
	FROM STAGING.STREAM_STG_EMPL_Insert S
    LEFT JOIN TARGET.EMPL_SCD2 T
           ON T.EMP_ID = S.EID
          AND T.EXPIRY_DATETIME IS NULL
    WHERE METADATA$ACTION = 'INSERT'
      AND (
            T.EMP_ID IS NULL                 -- brand new key
        OR  T.EMP_NAME        IS DISTINCT FROM S.ename
        OR  T.DATE_OF_BIRTH   IS DISTINCT FROM S.dob
        OR  T.EMAIL_ID        IS DISTINCT FROM S.mail
        OR  T.PHONE_NUMBER    IS DISTINCT FROM S.phone
        OR  T.SALARY          IS DISTINCT FROM S.SALARY
        OR  T.DEPARTMENT      IS DISTINCT FROM S.dept
        OR  T.WORK_LOCATION   IS DISTINCT FROM S.loc
      )
    ;

    RETURN 'SCD Type-2 Merge Completed Successfully at ' || cur_ts;

END;
;
