/**********************************************************************************
Stored Procedures:
We write stored procedures
1. When there is a need to run set of SQL statements together.
2. Dynamically prepare and execute SQL statements based on the parameters given.
3. When there is a need to run SQL statements based on some conditions.
4. When there is a need to run one or more SQL statements in loop.  
************************************************************************************/

Creating a Procedure:
CREATE <OR REPLACE> PROCEDURE PROCEDURE_NAME(Parameters)
RETURNS .. 
LANGUAGE.. 
EXECUTE AS ..
$$
…….
$$
Executing or Running or Calling a Procedure:
CALL PROCEDURE_NAME(Parameters);
In some databases: EXEC PROCEDURE_NAME(Parameters);
Dropping a Procedure:
DROP PROCEDURE_NAME(Parameters);

4 sectionss
1. CREATE section
2. DECLARE section
3. BODY section
4. EXCEPTION section
