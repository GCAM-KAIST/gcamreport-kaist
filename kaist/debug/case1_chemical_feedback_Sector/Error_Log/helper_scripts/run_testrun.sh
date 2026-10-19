#!/usr/bin/env bash
# Runs Testrun.R unattended: waits until the report is written and the Shiny UI reports "Listening on",
# then stops the R process (the UI would otherwise block forever).
PKG="/c/Users/pjhan/Desktop/git/iam_models/GCAM/gcamreport-integrated/gcamreport-temp"
LOG="$PKG/debug/case1_chemical_feedback_Sector/Error_Log/testrun_v9.1.log"
cd "$PKG" || exit 1
"/c/Program Files/R/R-4.6.1/bin/Rscript.exe" Testrun.R > "$LOG" 2>&1 &
RPID=$!
echo "Testrun.R started (bash pid $RPID) at $(date)"
for i in $(seq 1 240); do
  if grep -qE "Listening on http|Execution halted|^Error" "$LOG"; then break; fi
  sleep 15
done
echo "--- status at $(date) ---"
grep -E "Listening on|Execution halted|^Error|Standardized dataset saved|Launching UI|Inf variables|NA variables" "$LOG" | cut -c1-200
powershell -NoProfile -Command "Get-CimInstance Win32_Process | Where-Object { (\$_.Name -eq 'Rscript.exe' -or \$_.Name -eq 'Rterm.exe') -and \$_.CommandLine -like '*Testrun.R*' } | ForEach-Object { 'stopping ' + \$_.ProcessId; Stop-Process -Id \$_.ProcessId -Force }"
echo "TESTRUN WRAPPER DONE"
