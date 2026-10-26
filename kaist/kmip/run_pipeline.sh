#!/bin/bash
# KMIP pipeline in one command: step1 (one worker per scenario) -> step2 -> step4 -> step5 -> step6 -> step7.
#
# Usage (from the repo root):
#   kaist/kmip/run_pipeline.sh kaist/kmip/config/<run>.R [--from N] [--to N]
# --from / --to limit the steps (e.g. --from 2 after a step1 that already ran). Step3 (new
# mapping) is never run here. Step7 runs only when the settings file has compare_a_file.
# Logs: {output_dir}/logs/<date>/step*.log. Set KAIST_PYTHON for the step4 submission workbook
# and QUARTO_BIN if quarto is not on PATH.
set -u
cfg=${1:?settings file, e.g. kaist/kmip/config/kaist9_low26.R}; shift
from=1; to=7
while [ $# -gt 0 ]; do
  case "$1" in
    --from) from=$2; shift 2 ;;
    --to)   to=$2;   shift 2 ;;
    *) echo "unknown option $1"; exit 2 ;;
  esac
done
[ -f "$cfg" ] || { echo "settings file not found: $cfg"; exit 2; }
export KAIST_CONFIG=$cfg

out=$(Rscript -e 'suppressMessages(source("kaist/core/config.R")); cat(output_dir)' 2>/dev/null | tail -n 1)
[ -d "$out" ] || { echo "cannot read output_dir from $cfg"; exit 2; }
has_compare=$(Rscript -e 'suppressMessages(source("kaist/core/config.R")); cat(exists("compare_a_file"))' 2>/dev/null | tail -n 1)
L=$out/logs/$(date +%Y-%m-%d_%H%M); mkdir -p "$L"
echo "settings $cfg | output $out | logs $L | steps $from-$to"

run_step() {  # run_step <n> <script>
  local n=$1 s=$2
  [ "$n" -lt "$from" ] || [ "$n" -gt "$to" ] && return 0
  echo "[$(date +%H:%M:%S)] step$n $s"
  Rscript "$s" > "$L/step$n.log" 2>&1 || { echo "step$n FAILED, see $L/step$n.log"; tail -n 20 "$L/step$n.log"; exit 1; }
}
run_step 1 kaist/core/tools/step1_parallel.R
run_step 2 kaist/kmip/step2_process_data.R
run_step 4 kaist/kmip/step4_fill_template.R
run_step 5 kaist/kmip/step5_validate.R
run_step 6 kaist/kmip/step6_plots.R
if [ "$has_compare" = "TRUE" ]; then run_step 7 kaist/kmip/step7_compare.R; else echo "step7 skipped (no compare_a_file in $cfg)"; fi
grep -A5 "validation summary" "$L/step5.log" 2>/dev/null
echo "[$(date +%H:%M:%S)] done"
