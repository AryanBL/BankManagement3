#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT=/workspace
DATABASE_NAME=BankManagement
MSSQL_HOST="${MSSQL_HOST:-mssql}"
MSSQL_PORT="${MSSQL_PORT:-1433}"

cd "$PROJECT_ROOT"

for candidate in /opt/mssql-tools18/bin/sqlcmd /opt/mssql-tools/bin/sqlcmd; do
  if [[ -x "$candidate" ]]; then
    SQLCMD="$candidate"
    break
  fi
done

if [[ -z "${SQLCMD:-}" ]]; then
  echo "ERROR: sqlcmd was not found in the initializer image." >&2
  exit 2
fi

required=(
  MSSQL_SA_PASSWORD
  BANK_APP_PASSWORD
  BANK_REPORT_PASSWORD
  BANK_AUDITOR_PASSWORD
  BANK_HIGHADMIN_REPORT_PASSWORD
  BANK_MAINTENANCE_PASSWORD
)

for name in "${required[@]}"; do
  if [[ -z "${!name:-}" ]]; then
    echo "ERROR: required environment variable $name is empty." >&2
    exit 2
  fi
done

validate_complexity() {
  local name="$1"
  local value="${!name}"

  if (( ${#value} < 12 )) \
     || [[ ! "$value" =~ [A-Z] ]] \
     || [[ ! "$value" =~ [a-z] ]] \
     || [[ ! "$value" =~ [0-9] ]] \
     || [[ ! "$value" =~ [^[:alnum:]] ]]; then
    echo "ERROR: $name must be at least 12 characters and contain uppercase, lowercase, a digit, and a symbol." >&2
    exit 2
  fi
}

for name in "${required[@]}"; do
  validate_complexity "$name"
done

# The five Bank* values are substituted into N'...' SQL string literals and
# also passed through SQLCMD's -v parser. Reject ambiguous characters early.
for name in BANK_APP_PASSWORD BANK_REPORT_PASSWORD BANK_AUDITOR_PASSWORD BANK_HIGHADMIN_REPORT_PASSWORD BANK_MAINTENANCE_PASSWORD; do
  value="${!name}"
  if [[ "$value" == *"'"* \
     || "$value" == *'"'* \
     || "$value" == *$'\n'* \
     || "$value" == *$'\r'* \
     || "$value" == *'$('* ]]; then
    echo "ERROR: $name contains a character sequence unsafe for SQLCMD substitution." >&2
    echo "Avoid single/double quotes, newlines, carriage returns, and \$(... sequences)." >&2
    exit 2
  fi
done

export SQLCMDPASSWORD="$MSSQL_SA_PASSWORD"

sqlcmd_base=(
  "$SQLCMD"
  -S "${MSSQL_HOST},${MSSQL_PORT}"
  -U sa
  -C
  -b
  -r 1
  -l 30
  -v
  "BankAppPassword=$BANK_APP_PASSWORD"
  "BankReportPassword=$BANK_REPORT_PASSWORD"
  "BankAuditorPassword=$BANK_AUDITOR_PASSWORD"
  "BankHighAdminReportPassword=$BANK_HIGHADMIN_REPORT_PASSWORD"
  "BankMaintenancePassword=$BANK_MAINTENANCE_PASSWORD"
)

run_file() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    echo "ERROR: SQL installer file not found: $file" >&2
    exit 3
  fi

  echo
  echo "==> Running ${file#$PROJECT_ROOT/}"
  "${sqlcmd_base[@]}" -i "$file"
}

query_scalar() {
  local database="$1"
  local query="$2"
  "${sqlcmd_base[@]}" \
    -d "$database" \
    -h -1 \
    -W \
    -Q "SET NOCOUNT ON; $query" \
    | tr -d '\r' \
    | awk 'NF {print $1; exit}'
}

wait_for_agent() {
  local attempt state
  for attempt in $(seq 1 30); do
    if state="$(query_scalar master "SELECT CASE WHEN EXISTS (SELECT 1 FROM sys.dm_server_services WHERE servicename LIKE N'SQL Server Agent%' AND status_desc = N'Running') THEN 1 ELSE 0 END;" 2>/dev/null)" \
       && [[ "$state" == "1" ]]; then
      echo "SQL Server Agent is running."
      return 0
    fi
    sleep 2
  done

  echo "WARNING: SQL Server Agent did not report Running within 60 seconds." >&2
  echo "The jobs will still be created; verify Agent after startup." >&2
}

echo "SQL Server is healthy. Synchronizing database logins..."
run_file "$PROJECT_ROOT/database/install/01_create_database_and_logins.sqlcmd"

marker_exists="$(query_scalar "$DATABASE_NAME" "SELECT CASE WHEN OBJECT_ID(N'dbo.__DeploymentMetadata', N'U') IS NULL THEN 0 ELSE 1 END;")"
force_rebuild="${FORCE_DB_REBUILD:-false}"

if [[ "$marker_exists" != "1" || "$force_rebuild" == "true" ]]; then
  if [[ "$force_rebuild" == "true" ]]; then
    echo "WARNING: FORCE_DB_REBUILD=true; existing BankManagement project data will be deleted."
  fi

  run_file "$PROJECT_ROOT/database/install/02_install_bankmanagement_database.sqlcmd"
  run_file "$PROJECT_ROOT/database/install/03_install_security_and_views.sqlcmd"

  if [[ "${LOAD_SAMPLE_DATA:-false}" == "true" ]]; then
    run_file "$PROJECT_ROOT/database/install/04_optional_sample_data.sqlcmd"
  fi


else
  echo "Existing Docker deployment marker found; destructive schema rebuild skipped."
fi

# Record the deployment-file version on every successful initializer run,
# including nondestructive restarts that skip schema rebuilding.
"${sqlcmd_base[@]}" -d "$DATABASE_NAME" -Q "
  SET NOCOUNT ON;
  IF OBJECT_ID(N'dbo.__DeploymentMetadata', N'U') IS NULL
  BEGIN
    CREATE TABLE dbo.__DeploymentMetadata
    (
      DeploymentKey NVARCHAR(100) NOT NULL PRIMARY KEY,
      DeploymentValue NVARCHAR(4000) NULL,
      UpdatedAt DATETIME2(0) NOT NULL
        CONSTRAINT DF_DeploymentMetadata_UpdatedAt DEFAULT SYSUTCDATETIME()
    );
  END;

  MERGE dbo.__DeploymentMetadata AS T
  USING
  (
    SELECT
      N'container-schema-version' AS DeploymentKey,
      N'2026-07-wsl-2' AS DeploymentValue
  ) AS S
    ON T.DeploymentKey = S.DeploymentKey
  WHEN MATCHED THEN
    UPDATE SET
      DeploymentValue = S.DeploymentValue,
      UpdatedAt = SYSUTCDATETIME()
  WHEN NOT MATCHED THEN
    INSERT (DeploymentKey, DeploymentValue)
    VALUES (S.DeploymentKey, S.DeploymentValue);"

if [[ "${INSTALL_AGENT_JOBS:-true}" == "true" ]]; then
  wait_for_agent
  run_file "$PROJECT_ROOT/database/install/05_install_agent_jobs.sqlcmd"
else
  echo "SQL Server Agent job installation disabled by INSTALL_AGENT_JOBS=false."
fi

echo
"${sqlcmd_base[@]}" -d "$DATABASE_NAME" -Q "
  SELECT
    DB_NAME() AS DatabaseName,
    COUNT(CASE WHEN type = 'P' THEN 1 END) AS ProcedureCount,
    COUNT(CASE WHEN type = 'U' THEN 1 END) AS TableCount
  FROM sys.objects
  WHERE is_ms_shipped = 0;"

echo "Database initialization completed successfully."
