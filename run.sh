#/bin/bash

LOG_FILE=servers.log

# Run sass, coffeescript and web server
echo "Starting Sass..."
sass --scss --watch css/scss:css > $LOG_FILE 2>&1 &
SASS_PID=$!
echo "Starting Coffeescript..."
coffee -o js/ -wc js/coffee/ > $LOG_FILE 2>&1 &
COFFEE_PID=$!
echo "Starting python web server..."
python -m SimpleHTTPServer > $LOG_FILE 2>&1 &
PYTHON_PID=$!

control_c()
{
	echo "Exiting..."
	cleanup
	exit
}

cleanup(){
	for pid in $SASS_PID $COFFEE_PID $PYTHON_PID; do
		kill $pid
	done
}

trap control_c SIGINT

while true; do
	sleep 3
done

