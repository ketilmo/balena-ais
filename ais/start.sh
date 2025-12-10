#!/usr/bin/env bash
set -e

# Check if service has been disabled through the DISABLED_SERVICES environment variable.
if [[ ",$(echo -e "${DISABLED_SERVICES}" | tr -d '[:space:]')," = *",$BALENA_SERVICE_NAME,"* ]]; then
        echo "$BALENA_SERVICE_NAME is manually disabled. Sending request to stop the service:"
        curl --fail --retry 86400 --retry-delay 1 --retry-all-errors --header "Content-Type:application/json" "$BALENA_SUPERVISOR_ADDRESS/v2/applications/$BALENA_APP_ID/stop-service?apikey=$BALENA_SUPERVISOR_API_KEY" -d '{"serviceName": "'$BALENA_SERVICE_NAME'"}'
        echo " "
        balena-idle
fi

# Verify that all the required varibles are set before starting up the application.
echo "Verifying settings..."
echo " "
sleep 2
missing_variables=false

# Begin defining all the required configuration variables.
[ -z "$LAT" ] && echo "Receiver latitude is missing, will abort startup." && missing_variables=true || echo "Receiver latitude is set: $LAT"
[ -z "$LON" ] && echo "Receiver longitude is missing, will abort startup." && missing_variables=true || echo "Receiver longitude is set: $LON"
[ -z "$AIS_STATION_NAME" ] && echo "Receiver station name is missing, will abort startup." && missing_variables=true || echo "Receiver station name is set: $AIS_STATION_NAME"
[ -z "$AIS_DEVICE" ] && echo "Receiver device ID is missing, will abort startup." && missing_variables=true || echo "Receiver device ID is set: $AIS_DEVICE"

# Parse dynamic AIS feed configurations
# Format: AIS_FEED_<NAME>=IP:PORT or AIS_FEED_<NAME>=IP:PORT|EXTRA ARGUMENTS
# Examples:
#   AIS_FEED_LOCAL=127.0.0.1:10110
#   AIS_FEED_REMOTE=192.168.0.1:4002|JSON ON

# Build AIS-catcher configuration from validated variables
AIS_CONFIG="-d $AIS_DEVICE -N 8100 -gr RTLAGC on TUNER auto -a 192K -p 53 -v 10 -M DT -N REALTIME on -N STATION $AIS_STATION_NAME -N LAT $LAT LON $LON SHARE_LOC on"

AIS_FEEDS=""
echo "Scanning for AIS feed configurations..."
feed_error=false

for var in $(compgen -e | grep "^AIS_FEED_" | sort); do
    feed_value="${!var}"
    
    if [ -z "$feed_value" ]; then
        echo "Warning: $var is empty, skipping"
        continue
    fi
    
    # Split on pipe to separate IP:PORT from extra arguments
    # Format: IP:PORT|EXTRA_ARGUMENTS or just IP:PORT
    IFS='|' read -r endpoint extra_args <<< "$feed_value"
    
	# Validate IP:PORT or HOSTNAME:PORT format
	if [[ ! "$endpoint" =~ ^([a-zA-Z0-9.-]+):([0-9]{1,5})$ ]]; then
	    echo "ERROR: $var has invalid format: $feed_value"
	    echo "       Expected format: IP:PORT, HOSTNAME:PORT or IP:PORT|EXTRA ARGUMENTS"
	    echo "       Example: 192.168.1.100:5000 or feed.example.com:5000 or 192.168.1.100:5000|JSON ON"
	    feed_error=true
	    continue
	fi

	host="${BASH_REMATCH[1]}"
	port="${BASH_REMATCH[2]}"

	# Validate port range
	if [ "$port" -gt 65535 ]; then
	    echo "ERROR: $var has invalid port number: $port (must be 1-65535)"
	    feed_error=true
	    continue
	fi

	# Build the feed string
	if [ -n "$extra_args" ]; then
	    AIS_FEEDS="$AIS_FEEDS -u $host $port $extra_args"
	    echo "Found feed: $var = $host $port $extra_args"
	else
	    AIS_FEEDS="$AIS_FEEDS -u $host $port"
	    echo "Found feed: $var = $host $port"
	fi
done

if [ "$feed_error" = true ]; then
    echo " "
    echo "ERROR: One or more AIS feed configurations are invalid, aborting..."
    echo " "
    balena-idle
fi

if [ -z "$AIS_FEEDS" ]; then
    echo "No AIS feeds configured (no AIS_FEED_* variables found)"
else
    echo "Configured feeds:$AIS_FEEDS"
fi

# End defining all the required configuration variables.
echo " "
if [ "$missing_variables" = true ]
then
        echo "Settings missing, aborting..."
        echo " "
        balena-idle
fi

echo "Settings verified, proceeding with startup."
echo " "

# Variables are verified – continue with startup procedure.
# Start AIS-catcher and put it in the background.
/usr/local/bin/AIS-catcher $AIS_CONFIG $AIS_FEEDS &

# Wait for any services to exit.
wait -n
