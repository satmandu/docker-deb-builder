#!/bin/bash
tail -F /tmp/build.log --pid=$(cat /flag/main)| \
grep --line-buffered -v \
-e "waitfor(): sleep" \
-e "waitfor(): wait_proc" \
-e "waitfor(): echo \'scale" \
-e "waitfor(): bc"
