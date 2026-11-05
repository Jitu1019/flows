#!/bin/sh
# Runs the DevTools chat load test (devtools/chat-load.yamlflow.yaml).
# Usage: scripts/chat-load.sh <devtools flow run args...>
#   scripts/chat-load.sh chat-session                         one session, per-step table
#   scripts/chat-load.sh --scenario chat-ramp --vus-scale 2   load scenario
# The flow asks for the stream ID in a macOS dialog (once per run). Set ZOOP_STREAM_ID
# to skip it. Needs ZOOP_CHAT_MOBILES + ZOOP_TEST_OTP in .env. Each session logs in itself.
set -eu
cd "$(dirname "$0")/.."

set -a
. ./.env
set +a

: "${ZOOP_CHAT_MOBILES:?Set ZOOP_CHAT_MOBILES in .env (comma-separated test numbers).}"

exec devtools flow run devtools/chat-load.yamlflow.yaml "$@"
