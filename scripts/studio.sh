#!/bin/sh
# Starts DevTools Studio with the values its flows read from the environment:
#   auth-journey   ZOOP_TEST_MOBILE, ZOOP_TEST_OTP                      (.env)
#   chat-session   ZOOP_CHAT_MOBILES, ZOOP_TEST_OTP (.env). It asks for the stream ID
#                  in a dialog on every run.
# Studio only reads its environment at launch, so a running Studio is quit first.
# Usage: npm run studio
set -eu
cd "$(dirname "$0")/.."

set -a
. ./.env
set +a

if pgrep -xq DevTools-Studio; then
  osascript -e 'quit app "DevTools-Studio"'
  while pgrep -xq DevTools-Studio; do sleep 0.5; done
fi

open -a DevTools-Studio \
  --env "ZOOP_TEST_MOBILE=$ZOOP_TEST_MOBILE" \
  --env "ZOOP_TEST_OTP=$ZOOP_TEST_OTP" \
  --env "ZOOP_CHAT_MOBILES=${ZOOP_CHAT_MOBILES:-}"
