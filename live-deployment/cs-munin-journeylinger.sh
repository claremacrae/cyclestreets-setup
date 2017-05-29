#!/bin/bash
#	Generates Journey planner peformance data for munin
#
# SYNOPSIS
# 	munin-run journeylinger [config]
#
# DESCRIPTION
# 	If the optional argument config is supplied (as the plain string: config), this script
#	returns a summary of the parameters provided by this munin plugin.
#	Without that argument the values of those parameters are returned.
#
# Dependencies
#	munin-node
#
# Create a link to this script from the munin configuration:
# sudo ln -s /opt/cyclestreets-setup/live-deployment/cs-munin-journeylinger.sh /etc/munin/plugins/journeylinger
#
# Then restart munin node
# sudo systemctl restart munin-node
#
# Example calls
# sudo munin-run cyclestreets config
# sudo munin-run cyclestreets
#
# Remove
# sudo rm /etc/munin/plugins/cyclestreets
#
# See also
# https://dev.cyclestreets.net/wiki/ServerMonitoring
# http://guide.munin-monitoring.org/en/latest/develop/plugins/howto-write-plugins.html

### CREDENTIALS ###

# Get the script directory see: http://stackoverflow.com/a/246128/180733
# The multi-line method of geting the script directory is needed because this script is likely symlinked
SOURCE="${BASH_SOURCE[0]}"
DIR="$( dirname "$SOURCE" )"
while [ -h "$SOURCE" ]
do 
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
  DIR="$( cd -P "$( dirname "$SOURCE"  )" && pwd )"
done
DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"

# Use this to remove the ../
ScriptHome=$(readlink -f "${DIR}/..")

# Name of the credentials file
configFile=${ScriptHome}/.config.sh

# Generate your own credentials file by copying from .config.sh.template
if [ ! -x ${configFile} ]; then
    echo "#	The config file, ${configFile}, does not exist or is not excutable - copy your own based on the ${configFile}.template file."
    exit 1
fi

# Load the credentials
. ${configFile}


## Main body of script

## Public functions as called by munin

# Outputs the config of this plugin
output_config() {
    echo "graph_title CycleStreets Journey Linger"
    echo "graph_category CycleStreets"
    echo "graph_vlabel Milliseconds"
    
    # Use an upper limit of 3 seconds so making it easier to compare with across servers
    echo "graph_args -l 0 --upper-limit 3000"
    echo "journey_linger.label Journey linger"

    # Note spelling of this field :-)
    echo "journey_linger.colour 4488ee" 
    echo "journey_linger.warning 600"
    echo "journey_linger.critical 700"
}

# Outputs the statistics
output_values() {
    printf "journey_linger.value %d\n" $(journey_linger)
}

# Explain arguments to this script
output_usage() {
    printf >&2 "%s - CycleStreets graphs\n" ${0##*/}
    printf >&2 "Usage: %s [config]\n" ${0##*/}
}

## Internal functions that provide the statistics

# Number of itineraries in a five minute period
journey_linger() {
    python ${ScriptHome}/utility/readLogFile.py ${websitesLogsFolder}/${csHostname}-access.log
}



# Run the above functions, according to the arguments given to this script

case $# in
    0)
        output_values
        ;;
    1)
        case $1 in
            config)
                output_config
                ;;
            *)
                output_usage
                exit 1
                ;;
        esac
        ;;
    *)
        output_usage
        exit 1
        ;;
esac

# End of file
