#!/bin/bash
tail -F /tmp/build.log --pid=$(cat /flag/main)| \
grep --line-buffered -v \
-e "waitfor(): sleep" \
-e "waitfor(): wait_proc" \
-e "waitfor(): echo 'scale" \
-e "waitfor(): bc" \
-e "PrintLog(): ts" \
-e "wait_file(): grep -q -m1 ''" \
-e "PrintLog(): local logFile=/tmp/wait.log" \
-e "PrintLog(): [[ ! -e /tmp/wait.log ]]" \
-e "PrintLog(): [[ -e /tmp/wait.log ]]" \
-e ": sleep" \
-e ": wait_proc" \
-e ": echo 'scale" \
-e ": bc" \
-e ": ts" \
-e ": grep -q -m1 ''" \
-e ": local logFile=/tmp/wait.log" \
-e ": [[ ! -e /tmp/wait.log ]]" \
-e ": [[ -e /tmp/wait.log ]]" \
-e ": spinnerwait(): for" \
-e ": spinnerwait(): tput " \
-e ": spinnerwait(): sleep" \
-e ": spinnerwait(): pgrep" \
-e ": spinnerwait(): printf"
