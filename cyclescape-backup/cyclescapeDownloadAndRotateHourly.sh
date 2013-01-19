#!/bin/bash
#	This file is one of the cyclescape backup tasks that runs on the CycleStreets backup machine
#
#	This file downloads dumps from www.cyclescape.org to the backup machine.
#
#	The server at www.cyclescape.org should generate backups of
#	* database - less than 1M
#	* toolkit assets - around 100M (Feb 2012) (500M Jan 2013)
#	as zipped files.
#	Both files should also have .md5 files containing the md5 strings associated with them.
#	This script looks at the remote md5 files to determine whether they and the dumps are ready to download.

### Stage 1 - general setup

# Ensure this script is NOT run as root (it should be run as cyclestreets)
if [ "$(id -u)" = "0" ]; then
    echo "#	This script must NOT be run as root." 1>&2
    exit 1
fi

# Bomb out if something goes wrong
set -e

# Lock directory
lockdir=/var/lock/cyclestreets
mkdir -p $lockdir

# Set a lock file; see: http://stackoverflow.com/questions/7057234/bash-flock-exit-if-cant-acquire-lock/7057385
(
	flock -n 9 || { echo 'CycleStreets Cyclescape hourly backup is already in progress' ; exit 1; }

### CREDENTIALS ###

# Get the script directory see: http://stackoverflow.com/a/246128/180733
# The multi-line method of geting the script directory is needed because this script is likely symlinked from cron
SOURCE="${BASH_SOURCE[0]}"
DIR="$( dirname "$SOURCE" )"
while [ -h "$SOURCE" ]
do 
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
  DIR="$( cd -P "$( dirname "$SOURCE"  )" && pwd )"
done
DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
SCRIPTDIRECTORY=$DIR

# Define the location of the credentials file relative to script directory
configFile=../.config.sh

# Generate your own credentials file by copying from .config.sh.template
if [ ! -e $SCRIPTDIRECTORY/${configFile} ]; then
    echo "# The config file, ${configFile}, does not exist - copy your own based on the ${configFile}.template file." 1>&2
    exit 1
fi

# Load the credentials
. $SCRIPTDIRECTORY/${configFile}


# Main body

#	Folder locations
server=www.cyclescape.org
folder=/websites/cyclescape/backup
download=${SCRIPTDIRECTORY}/../utility/downloadDumpAndMd5.sh
rotateHourly=${SCRIPTDIRECTORY}/../utility/rotateHourly.sh

#	Download
$download $administratorEmail $server $folder cyclescapeDB.sql.gz
$download $administratorEmail $server $folder toolkitShared.tar.bz2

#	Rotate
$rotateHourly $folder cyclescapeDB.sql.gz
$rotateHourly $folder toolkitShared.tar.bz2

# Remove the lock file
) 9>$lockdir/cyclescapeDownloadAndRotateHourly

# End of file
