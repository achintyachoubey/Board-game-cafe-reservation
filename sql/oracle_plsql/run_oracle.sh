#!/usr/bin/env bash
# Run the Oracle PL/SQL appendix in a throw-away Oracle Database Free container
# (gvenzl/oracle-free) and save the SQL*Plus output in output/*.out.
#   bash sql/oracle_plsql/run_oracle.sh
# Needs Docker and ~2 GB of free RAM; the first start takes 1-2 minutes.
set -euo pipefail
cd "$(dirname "$0")"
IMAGE="${ORACLE_IMAGE:-gvenzl/oracle-free:23-slim}"
NAME=cafe_oracle
if ! docker ps --format '{{.Names}}' | grep -qx "$NAME"; then
  docker run -d --name "$NAME" -e ORACLE_PASSWORD=OraclePw2026 \
    -e APP_USER=cafe -e APP_USER_PASSWORD=cafe "$IMAGE" >/dev/null
fi
echo "waiting for Oracle to start ..."
until docker logs "$NAME" 2>&1 | grep -q "DATABASE IS READY TO USE"; do sleep 5; done
mkdir -p output
for f in 01_schema 02_programs 03_demo; do
  { echo "SET ECHO ON"; cat "$f.sql"; echo "EXIT"; } \
    | docker exec -i "$NAME" sqlplus -s cafe/cafe@//localhost:1521/FREEPDB1 > "output/$f.out" 2>&1
  echo "ran $f.sql -> output/$f.out"
done
docker exec "$NAME" bash -c 'echo "SELECT banner_full FROM v\$version;" | sqlplus -s cafe/cafe@//localhost:1521/FREEPDB1' \
  > output/version.out
echo "done (stop the container with: docker rm -f $NAME)"
