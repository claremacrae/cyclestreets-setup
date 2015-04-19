#!/bin/bash
# 
# SYNOPSIS
#	installLocalLatestEdition.sh
#
# DESCRIPTION
#	Used on a server that provides both the live and import deployments. Ie. usually a developer machine.
#	This script moves the files generated by the latest import run to the website data area so they can be used for routing.
#	Afterwards use ./switchRoutingEdition.sh to use the new edition.
#
# Run as the cyclestreets user (a check is peformed after the config file is loaded).

echo "# $(date)	Install latest locally generated CycleStreets import routing edition"

# Ensure this script is NOT run as root
if [ "$(id -u)" = "0" ]; then
    echo "#	This script must not be be run as root." 1>&2
    exit 1
fi

# Bomb out if something goes wrong
set -e

# Lock directory
lockdir=/var/lock/cyclestreets
mkdir -p $lockdir

# Set a lock file; see: http://stackoverflow.com/questions/7057234/bash-flock-exit-if-cant-acquire-lock/7057385
(
	flock -n 9 || { echo '#	An import is already running' ; exit 1; }

### CREDENTIALS ###

# Get the script directory see: http://stackoverflow.com/a/246128/180733
# The second single line solution from that page is probably good enough as it is unlikely that this script itself will be symlinked.
DIR="$( cd -P "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

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

# Ensure this script is run as cyclestreets user
if [ ! "$(id -nu)" = "${username}" ]; then
    echo "#	This script must be run as user ${username}, rather than as $(id -nu)."
    exit 1
fi

# Check the import folder is defined
if [ -z "${importContentFolder}" ]; then
    echo "#	The import folder is not defined."
    exit 1
fi

# Check that the import finished correctly
if ! mysql -hlocalhost --batch --skip-column-names -e "call importStatus()" cyclestreets | grep "valid\|cellOptimised" > /dev/null 2>&1
then
    echo "# The import process did not complete. The routing service will not be started."
    exit 1
fi


### Determine latest import

# Check the import folder is defined
if [ -z "${importMachineEditions}" ]; then
    echo "#	The import output folder is not defined."
    exit 1
fi

# Read the folder of routing editions, one per line, newest first, getting first one
latestEdition=`ls -1t ${importMachineEditions} | head -n1`

# Abandon if not found
if [ -z "${latestEdition}" ]; then
	echo "# No editions found in ${importMachineEditions}"
	exit 1
fi

# Check this edition is not already installed
if [ -d ${websitesContentFolder}/data/routing/${latestEdition} ]; then
	echo "# Edition ${latestEdition} is already installed."
	exit 1
fi


#	Report finding
echo "#	Installing latest edition: ${latestEdition}"

# Create the new folder
mkdir -p ${websitesContentFolder}/data/routing/${latestEdition}

# Move the tsv files
mv ${importMachineEditions}/${latestEdition}/*.tsv ${websitesContentFolder}/data/routing/${latestEdition}

# Configure MySQL for routing
# During an import run these parameters may have been set to much larger values in order to process large data tables.
# Setting these parameters here will have the effect of reducing them from their import settings, at least until the next MySQL restart, when they will inherit the configuration values.
if [ -n "${routing_key_buffer_size}" ]; then
    echo "#	Configuring MySQL for serving routes"
    mysql -hlocalhost -e "set global key_buffer_size = ${routing_key_buffer_size};";
fi
if [ -n "${routing_max_heap_table_size}" ]; then
    mysql -hlocalhost -e "set global max_heap_table_size = ${routing_max_heap_table_size};";
fi
if [ -n "${routing_tmp_table_size}" ]; then
    mysql -hlocalhost -e "set global tmp_table_size = ${routing_tmp_table_size};";
fi

# Create a file that indicates the end of the script was reached - this can be tested for by the switching script
touch "${websitesContentFolder}/data/routing/${latestEdition}/installationCompleted.txt"

# Report completion and next steps
echo "# Installation completed, to switch routing service use: ./switch-routing-edition.sh ${latestEdition}"

# Remove the lock file - ${0##*/} extracts the script's basename
) 9>$lockdir/${0##*/}

# End of file
