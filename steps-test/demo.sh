#!/usr/bin/env bash
# demo.sh — shows the steps.sh checklist. Run: bash demo.sh   (or: bash demo.sh fail)
source "$(dirname "$0")/steps.sh"

function_detect_os() {
  . /etc/os-release
  echo "Detected $PRETTY_NAME"
  function_steps_set OS_NAME "$PRETTY_NAME"   # visible to later steps and the main script
}

function_slow_work() {
  for I in 1 2 3; do echo "working... $I"; sleep 1; done
}

function_break_things() {
  echo "about to fail"
  false                     # any failing command fails the step
  echo "never printed"
}

function_steps_init "Demo bootstrap" \
  "Detect operating system" \
  "Download things" \
  "Configure things" \
  "Optional extra" \
  "Final check"

function_step_run 1 function_detect_os
function_step_run 2 function_slow_work
if [[ ${1:-} == fail ]]; then function_step_run 3 function_break_things
else function_step_run 3 sleep 1; fi
function_step_skip 4 "not needed on $OS_NAME"
function_step_run 5 sleep 1
function_steps_finish
