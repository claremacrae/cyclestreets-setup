#!/bin/bash
# Script to install CycleStreets import sources and data on Ubuntu
#
# Tested on 14.04.2 LTS. View Ubuntu version using: lsb_release -a
# This script is idempotent - it can be safely re-run without destroying existing data
# It should be run after the website system has been installed.

echo "#	$(date)	CycleStreets Import System installation"

# Ensure this script is run as root
if [ "$(id -u)" != "0" ]; then
    echo "#	This script must be run as root." 1>&2
    exit 1
fi

# Bomb out if something goes wrong
set -e

### CREDENTIALS ###

# Get the script directory see: http://stackoverflow.com/a/246128/180733
# The second single line solution from that page is probably good enough as it is unlikely that this script itself will be symlinked.
DIR="$( cd -P "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SCRIPTDIRECTORY=$DIR

# Use this to remove the ../
ScriptHome=$(readlink -f "${DIR}/..")

# Name of the credentials file
configFile=../.config.sh

# Generate your own credentials file by copying from .config.sh.template
if [ ! -x ./${configFile} ]; then
    echo "#	The config file, ${configFile}, does not exist or is not excutable - copy your own based on the ${configFile}.template file." 1>&2
    exit 1
fi

# Load the credentials
. ./${configFile}

# Load common install script
. ${ScriptHome}/utility/installCommon.sh

# Need to add a check that CycleStreets main installation has been completed
if [ ! -d "${websitesContentFolder}" ]; then
    echo "#	Please install the main CycleStreets repo first"
    exit 1
fi

# For the time being [:] 14 Apr 2015 the import is a symbolic link
if [ ! -L "${importContentFolder}" ]; then

    # Create the symlink
    ln -s ${websitesContentFolder}/import ${importContentFolder}

fi

# Switch to import folder
cd ${importContentFolder}

# Create the settings file if it doesn't exist
phpConfig=.config.php
if [ ! -e ${phpConfig} ]
then
    cp -p .config.php.template ${phpConfig}
fi

# Setup the config?
if grep IMPORT_USERNAME_HERE ${phpConfig} >/dev/null 2>&1;
then

    # Make the substitutions
    echo "#	Configuring the import ${phpConfig}";
    sed -i \
-e "s/IMPORT_USERNAME_HERE/${mysqlImportUsername}/" \
-e "s/IMPORT_PASSWORD_HERE/${mysqlImportPassword}/" \
-e "s/MYSQL_ROOT_PASSWORD_HERE/${mysqlRootPassword}/" \
-e "s/ADMIN_EMAIL_HERE/${administratorEmail}/" \
-e "s/MySQL_KEY_BUFFER_SIZE_HERE/${import_key_buffer_size}/" \
-e "s/MySQL_MAX_HEAP_TABLE_SIZE_HERE/${import_max_heap_table_size}/" \
-e "s/MySQL_TMP_TABLE_SIZE_HERE/${import_tmp_table_size}/" \
	${phpConfig}
fi

# Check Osmosis has been installed
if [ ! -L /usr/local/bin/osmosis ]; then

    # Announce Osmosis installation
    # !! Osmosis uses MySQL and that needs to be configured to use character_set_server=utf8 and collation_server=utf8_unicode_ci which is currently set up (machine wide) by website installation.
    echo "#	$(date)	CycleStreets / Osmosis installation"

    # Prepare the apt index
    apt-get update > /dev/null

    # Osmosis requires java
    apt-get -y install openjdk-7-jre

    # Create folder
    mkdir -p /usr/local/osmosis

    # wget the latest to here
    if [ ! -e /usr/local/osmosis/osmosis-latest.tgz ]; then
	wget -O /usr/local/osmosis/osmosis-latest.tgz http://dev.openstreetmap.org/~bretth/osmosis-build/osmosis-latest.tgz
    fi

    # Create a folder for the new version
    mkdir -p /usr/local/osmosis/osmosis-0.43.1

    # Unpack into it
    tar xzf /usr/local/osmosis/osmosis-latest.tgz -C /usr/local/osmosis/osmosis-0.43.1

    # Remove the download archive
    rm -f /usr/local/osmosis/osmosis-latest.tgz

    # Repoint current to the new install
    rm -f /usr/local/osmosis/current

    # Whatever the version number is here - replace the 0.43.1
    ln -s /usr/local/osmosis/osmosis-0.43.1 /usr/local/osmosis/current

    # This last bit only needs to be done first time round, not for upgrades. It keeps the binary pointing to the current osmosis.
    if [ ! -L /usr/local/bin/osmosis ]; then
	ln -s /usr/local/osmosis/current/bin/osmosis /usr/local/bin/osmosis
    fi

    # Announce completion
    echo "#	Completed installation of osmosis"
fi

# Database setup
# Useful binding
mysql="mysql -hlocalhost"

# Users are created by the grant command if they do not exist, making these idem potent.
# The grant is relative to localhost as it will be the apache server that authenticates against the local mysql.
${mysql} -e "grant select, reload, file, super, lock tables, event, trigger on * . * to '${mysqlImportUsername}'@'localhost' identified by '${mysqlImportPassword}' with max_queries_per_hour 0 max_connections_per_hour 0 max_updates_per_hour 0 max_user_connections 0;"

# Useful binding
importpermissions="grant select, insert, update, delete, create, drop, index, alter, create temporary tables, lock tables, create view, show view, create routine, alter routine, execute on"

${mysql} -e "${importpermissions} \`planetExtractOSM%\` . * to '${mysqlImportUsername}'@'localhost';"
${mysql} -e "${importpermissions} \`routing%\` . * to '${mysqlImportUsername}'@'localhost';"

# Elevation data - download 33GB of data, which expands to 180G.
# Tip: These are big files use this to resume a broken copy
# rsync --partial --progress --rsh=ssh user@host:remote_file local_file

# Make sure the target folder exists
${asCS} mkdir -p ${websitesBackupsFolder}/external

# Check if Ordnance Survey NTF data is desired and that it has not already been downloaded
if [ ! -z "${ordnanceSurveyDataFile}" -a ! -x ${websitesBackupsFolder}/${ordnanceSurveyDataFile} ]; then

	# Report
	echo "#	Starting download of OS NTF data 48M"

	# Download
	wget http://cyclestreets:${datapassword}@data.cyclestreets.net/${ordnanceSurveyDataFile} -O ${websitesBackupsFolder}/${ordnanceSurveyDataFile}

	# Report
	echo "#	Starting installation of OS NTF data"

	# Create folder and unpack
	mkdir -p ${importContentFolder}/data/elevation/ordnanceSurvey
	tar xf ${websitesBackupsFolder}/${ordnanceSurveyDataFile} -C ${importContentFolder}/data/elevation/ordnanceSurvey
fi

# Check if srtm data is desired and that it has not already been downloaded
if [ ! -z "${srtmDataFile}" -a ! -x ${websitesBackupsFolder}/${srtmDataFile} ]; then

	# Report
	echo "#	Starting download of SRTM data 8.2G"

	# Download
	wget http://cyclestreets:${datapassword}@data.cyclestreets.net/${srtmDataFile} -O ${websitesBackupsFolder}/${srtmDataFile}

	# Report
	echo "#	Starting installation of SRTM data"

	# Create folder and unpack
	mkdir -p ${importContentFolder}/data/elevation/srtmV4.1/tiff
	tar xf ${websitesBackupsFolder}/${srtmDataFile} -C ${importContentFolder}/data/elevation/srtmV4.1
fi

# Check if ASTER data is desired and that it has not already been downloaded
if [ ! -z "${asterDataFile}" -a ! -x ${websitesBackupsFolder}/${asterDataFile} ]; then

	# Report
	echo "#	Starting download of ASTER data 25G"

	# Download
	wget http://cyclestreets:${datapassword}@data.cyclestreets.net/${asterDataFile} -O ${websitesBackupsFolder}/${asterDataFile}

	# Report
	echo "#	Starting installation of ASTER data"

	# Create folder and unpack
	mkdir -p ${importContentFolder}/data/elevation/asterV2/tiff
	tar xf ${websitesBackupsFolder}/${asterDataFile} -C ${importContentFolder}/data/elevation/asterV2
fi

# Confirm end of script
echo "#	$(date)	All now installed."

# Return true to indicate success
:

# End of file
