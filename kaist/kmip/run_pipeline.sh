#!/bin/bash
# KMIP pipeline in one command:
#   step1 report (one worker per scenario) -> step2 adjust -> step3 template -> step4 check -> step5 report
#
# Usage (from the repo root):
#   kaist/kmip/run_pipeline.sh kaist/kmip/config/<run>.R [--from N] [--to N]
# --from / --to limit the steps (e.g. --from 2 after a step1 that already ran). A settings
# file may set run_steps <- c(1, 2, 4, 5) to leave out steps (NMSF2 has no KMIP template).
# The mapping tool (kaist/kmip/make_mapping.R) is not part of a run.
# Logs: {output_dir}/logs/<date>/step*.log. Set QUARTO_BIN if quarto is not on PATH (step5).
set -u
cfg=${1:?settings file, e.g. kaist/kmip/config/kaist9_low26.R}; shift
from=1; to=5
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
run_steps=$(Rscript -e 'suppressMessages(source("kaist/core/config.R")); cat(if (exists("run_steps")) run_steps else 1:5)' 2>/dev/null | tail -n 1)
L=$out/logs/$(date +%Y-%m-%d_%H%M); mkdir -p "$L"
echo "settings $cfg | output $out | logs $L | steps $from-$to (run_steps: $run_steps)"

run_step() {  # run_step <n> <script>
  local n=$1 s=$2
  [ "$n" -lt "$from" ] || [ "$n" -gt "$to" ] && return 0
  case " $run_steps " in *" $n "*) ;; *) echo "step$n skipped (run_steps)"; return 0 ;; esac
  echo "[$(date +%H:%M:%S)] step$n $s"
  Rscript "$s" > "$L/step$n.log" 2>&1 || { echo "step$n FAILED, see $L/step$n.log"; tail -n 20 "$L/step$n.log"; exit 1; }
}
run_step 1 kaist/core/tools/step1_parallel.R
run_step 2 kaist/kmip/step2_adjust.R
run_step 3 kaist/kmip/step3_template.R
run_step 4 kaist/kmip/step4_check.R
run_step 5 kaist/kmip/step5_report.R
grep -A5 "check summary" "$L/step4.log" 2>/dev/null
echo "[$(date +%H:%M:%S)] done"
