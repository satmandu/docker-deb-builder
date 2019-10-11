#!/bin/bash
tail -F /tmp/build.log --pid=$(cat /flag/main)| grep --line-buffered -v "waitfor(): sleep" -v "waitfor(): wait_proc=" -v "waitfor(): echo \'scale=2" -v "waitfor(): bc"
