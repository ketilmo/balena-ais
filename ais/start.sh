#!/usr/bin/env bash
set -e

# Check if service has been disabled through the DISABLED_SERVICES environment variable.
if [[ ",$(echo -e "${DISABLED_SERVICES}" | tr -d '[:space:]')," = *",$BALENA_SERVICE_NAME,"* ]]; then
        echo "$BALENA_SERVICE_NAME is manually disabled. Sending request to stop the service:"
        curl --fail --retry 86400 --retry-delay 1 --retry-all-errors --header "Content-Type:application/json" "$BALENA_SUPERVISOR_ADDRESS/v2/applications/$BALENA_APP_ID/stop-service?apikey=$BALENA_SUPERVISOR_API_KEY" -d '{"serviceName": "'$BALENA_SERVICE_NAME'"}'
        echo " "
        balena-idle
fi

# Verify that all the required variables are set before starting up the application.
echo "Verifying settings..."
echo " "
sleep 2
missing_variables=false
config_error=false

# Begin defining all the required configuration variables.
[ -z "$LAT" ] && echo "Receiver latitude is missing, will abort startup." && missing_variables=true || echo "Receiver latitude is set: $LAT"
[ -z "$LON" ] && echo "Receiver longitude is missing, will abort startup." && missing_variables=true || echo "Receiver longitude is set: $LON"
[ -z "$AIS_STATION_NAME" ] && echo "Receiver station name is missing, will abort startup." && missing_variables=true || echo "Receiver station name is set: $AIS_STATION_NAME"
[ -z "$AIS_DEVICE" ] && echo "Receiver device ID is missing, will abort startup." && missing_variables=true || echo "Receiver device ID is set: $AIS_DEVICE"

# Function to parse output configurations
# Usage: parse_outputs "PREFIX" "CLI_FLAG"
# Example: parse_outputs "AIS_OUTPUT_UDP" "-u"
parse_outputs() {
    local prefix=$1
    local cli_flag=$2
    local output_string=""
    
    echo "Scanning for ${prefix} configurations..."
    
    for var in $(compgen -e | grep "^${prefix}_" | sort); do
        output_value="${!var}"
        
        if [ -z "$output_value" ]; then
            echo "Warning: $var is empty, skipping"
            continue
        fi
        
        # Split on pipe to get endpoint and arguments
        IFS='|' read -ra parts <<< "$output_value"
        
        # Build output string with cli flag and all parts
        output_string="$output_string $cli_flag"
        
        for part in "${parts[@]}"; do
            if [ -n "$part" ]; then
                output_string="$output_string $part"
            fi
        done
        
        echo "Found: $var = ${parts[@]}"
    done
    
    echo "$output_string"
}

# Parse all output types
# Format: AIS_OUTPUT_<TYPE>_<NAME>=VALUE|ARG1|ARG2|...
# Examples:
#   AIS_OUTPUT_UDP_LOCAL=127.0.0.1 10110
#   AIS_OUTPUT_UDP_REMOTE=192.168.0.1 4002|MSGFORMAT JSON_FULL
#   AIS_OUTPUT_HTTP_API=http://api.example.com:8080
#   AIS_OUTPUT_MQTT_BROKER=mqtt://username:password@127.0.0.1:1883|client_id aiscatcher|qos 0|topic data/ais|msgformat JSON_NMEA

AIS_OUTPUT_TCPS=$(parse_outputs "AIS_OUTPUT_TCPS" "-S")
AIS_OUTPUT_TCPC=$(parse_outputs "AIS_OUTPUT_TCPC" "-P")
AIS_OUTPUT_UDP=$(parse_outputs "AIS_OUTPUT_UDP" "-u")
AIS_OUTPUT_HTTP=$(parse_outputs "AIS_OUTPUT_HTTP" "-H")
AIS_OUTPUT_MQTT=$(parse_outputs "AIS_OUTPUT_MQTT" "-Q")

# Build base configuration
AIS_CONFIG="-d $AIS_DEVICE -N $AIS_WEB_PORT -gr RTLAGC on TUNER auto -a 192K -p 53 -v 10 -M DTM -N REALTIME on -N STATION $AIS_STATION_NAME -N LAT $LAT LON $LON SHARE_LOC on"

# Check for missing variables or configuration errors
echo " "
if [ "$missing_variables" = true ]; then
    echo "Required settings missing, aborting..."
    echo " "
    balena-idle
fi

if [ "$config_error" = true ]; then
    echo "Configuration errors detected, aborting..."
    echo " "
    balena-idle
fi

echo "Settings verified, proceeding with startup."
echo " "

# Start AIS-catcher with all configurations
/usr/local/bin/AIS-catcher $AIS_CONFIG $AIS_OUTPUT_TCPS $AIS_OUTPUT_TCPC $AIS_OUTPUT_UDP $AIS_OUTPUT_HTTP $AIS_OUTPUT_MQTT &

# Wait for any services to exit
wait -n