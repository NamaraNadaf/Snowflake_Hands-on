CREATE OR REPLACE PROCEDURE DB_DEV_N01.RAW.SP_INGEST_FILES( db string,sch string)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
DECLARE
    v_count NUMBER := 0;
    cur_ts  TIMESTAMP := CURRENT_TIMESTAMP();
    v_file STRING :='';
    stmt string;
      v_errors NUMBER := 0;
      error_file_name STRING := '';
      archive_file_name string;
    
    ------------------------------------------------------------------
    -- Step 1: CREATE CURSOR to get all NEW FILES from Stream 
    ------------------------------------------------------------------    
    cur CURSOR FOR 
      SELECT RELATIVE_PATH AS filename
      FROM DB_DEV_N01.RAW.ingest_dir_stream
      WHERE METADATA$ACTION = 'INSERT';   

BEGIN -- TRY    
EXECUTE IMMEDIATE 'USE DATABASE ' || db;
EXECUTE IMMEDIATE 'USE SCHEMA ' || sch;
    ------------------------------------------------------------------
    -- Step 2: Loop through new files and load each
    ------------------------------------------------------------------
    -- use database DB_DEV_N01;
    -- USE SCHEMA DB_DEV_N01.RAW;
    
    FOR rec IN cur DO
    v_file := rec.filename;
     -- v_file_pattern := CONCAT('.*', rec.filename, '.*');
    v_errors := 0;


stmt := 'COPY INTO DB_DEV_N01.RAW.EMP_DATA FROM @ingest_stage FILE_FORMAT = ''csvfmt'' FILES = ('''|| v_file ||''')  ON_ERROR = ''CONTINUE'' ';

  EXECUTE IMMEDIATE :stmt ;

 -- Validate the last COPY INTO operation in the current session
        -- SELECT * FROM TABLE(VALIDATE(RAW.EMP_DATA, JOB_ID => '_last'));


        -- Save validation results for later review
        CREATE OR REPLACE TABLE copy_errors AS
        SELECT * FROM TABLE(VALIDATE(RAW.EMP_DATA, JOB_ID => '_last'));

        --check count of copy_errors
        select count(*) into v_errors
        from copy_errors;

        IF (v_errors > 0) THEN
            -- error_file_name := 'Error_'||v_file || '_'||CURRENT_TIMESTAMP()||'.csv';
            error_file_name := v_file || '_' || TO_VARCHAR(CURRENT_TIMESTAMP(), 'YYYYMMDD_HH24MISS') || '.csv';

           stmt := 'COPY INTO @ingest_stage/errors/' || error_file_name || 
    ' FROM copy_errors FILE_FORMAT = (FORMAT_NAME = ''csvfmt'')';
           EXECUTE IMMEDIATE :stmt;

      -- Remove original file after copying to errors
        stmt := 'REMOVE @ingest_stage/' || v_file;
        EXECUTE IMMEDIATE :stmt;
            
        INSERT INTO RAW.FILE_INGEST_LOG 
        VALUES (:v_file, :cur_ts, 'FAILED');

        ELSE
        
        INSERT INTO RAW.FILE_INGEST_LOG 
        VALUES (:v_file, :cur_ts, 'SUCCESS');

archive_file_name := 'Archive_' || v_file || '_' || TO_VARCHAR(CURRENT_TIMESTAMP(), 'YYYYMMDD_HH24MISS') || '.csv';

stmt := 'COPY FILES INTO @ingest_stage/archive/' || archive_file_name || '/ FROM @ingest_stage FILES = (''' || v_file || ''')';
       EXECUTE IMMEDIATE :stmt;
      
       stmt := 'REMOVE @ingest_stage/' || v_file;
       EXECUTE IMMEDIATE :stmt;


END IF;
        v_count := v_count + 1;
    END FOR;
   RETURN 'Ingestion completed. Files processed = ' || v_count;

 END;



call DB_DEV_N01.RAW.SP_INGEST_FILES('DB_DEV_N01','RAW');