#!/bin/bash
tail -F /tmp/build.log --pid=$(cat /flag/main)| \
grep --line-buffered -v \
-e "waitfor(): sleep" \
-e "waitfor(): wait_proc" \
-e "waitfor(): echo 'scale" \
-e "waitfor(): bc"
-e "PrintLog(): ts"
-e "wait_file(): grep -q -m1 ''"
-e "PrintLog(): local logFile=/tmp/wait.log"
-e "PrintLog(): [[ ! -e /tmp/wait.log ]]"
-e "PrintLog(): [[ -e /tmp/wait.log ]]"
