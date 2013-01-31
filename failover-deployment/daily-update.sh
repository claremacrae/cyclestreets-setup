#!/bin/bash
# Script to update CycleStreets on a daily basis
# Tested on 12.10 (View Ubuntu version using 'lsb_release -a')

# This script is idempotent - it can be safely re-run without destroying existing data.

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
	flock -n 9 || { echo 'CycleStreets daily update is already running' ; exit 1; }

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
if [ ! -x $SCRIPTDIRECTORY/${configFile} ]; then
    echo "# The config file, ${configFile}, does not exist or is not excutable - copy your own based on the ${configFile}.template file." 1>&2
    exit 1
fi

# Load the credentials
. $SCRIPTDIRECTORY/${configFile}

# Logging
setupLogFile=$SCRIPTDIRECTORY/log.txt
touch ${setupLogFile}
#echo "#	CycleStreets daily update in progress, follow log file with: tail -f ${setupLogFile}"
echo "$(date)	CycleStreets daily update $(id)" >> ${setupLogFile}

# Ensure live machine has been defined
if [ -z "${liveMachineAddress}" ]; then
    echo "# A live machine must be defined in order to run updates" >> ${setupLogFile}
    exit 1
fi

# Ensure there is a cyclestreets user account
if [ ! id -u ${username} >/dev/null 2>&1 ]; then
	echo "$(date) User ${username} must exist: please run the main website install script" >> ${setupLogFile}
	exit 1
fi

# Ensure this script is run as cyclestreets user
if [ ! "$(id -nu)" = "${username}" ]; then
    echo "#	This script must be run as user ${username}, rather than as $(id -nu)." 1>&2
    exit 1
fi

# Ensure the main website installation is present
if [ ! -d ${websitesContentFolder}/data/routing -o ! -d $websitesBackupsFolder ]; then
	echo "$(date) The main website installation must exist: please run the main website install script" >> ${setupLogFile}
	exit 1
fi


### Stage 2 - CycleStreets regular tasks for www

#	Download and restore the CycleStreets database.
#	Folder locations
server=${liveMachineAddress}
folder=${websitesBackupsFolder}
download=${SCRIPTDIRECTORY}/../utility/downloadDumpAndMd5.sh

#	Download CyclesStreets Schema
$download $administratorEmail $server $folder www_schema_cyclestreets.sql.gz

#	Download & Restore CycleStreets database
$download $administratorEmail $server $folder www_cyclestreets.sql.gz

# Replace the cyclestreets database
echo "$(date)	Replacing CycleStreets db" >> ${setupLogFile}
mysql -hlocalhost -uroot -p${mysqlRootPassword} -e "drop database if exists cyclestreets;";
mysql -hlocalhost -uroot -p${mysqlRootPassword} -e "create database cyclestreets default character set utf8 collate utf8_unicode_ci;";
gunzip < /websites/www/backups/www_cyclestreets.sql.gz | mysql -hlocalhost -uroot -p${mysqlRootPassword} cyclestreets

#	Turn off pseudoCron to stop duplicated cronning from the backup machine
mysql cyclestreets -hlocalhost -uroot -p${mysqlRootPassword} -e "update map_config set pseudoCron = null;";

#	Sync the photomap
# Use option -O (omit directories from --times), necessary because apparently only owner (or root) can set a directory's mtime.
# rsync can produce other errors such as:
# rsync: mkstemp "/websites/www/content/data/photomap2/46302/.original.jpg.H3xy2f" failed: Permission denied (13)
# rsync: mkstemp "/websites/www/content/data/photomap2/46302/.rotated.jpg.Y3sb28" failed: Permission denied (13)
# these appear to be temporary files, possibly generated and owned by the system. Hard to track down and probably safe to ignore.
# Tolerate errors from rsync
set +e
rsync -rtO --cvs-exclude ${server}:${websitesContentFolder}/data/photomap ${websitesContentFolder}/data
rsync -rtO --cvs-exclude ${server}:${websitesContentFolder}/data/photomap2 ${websitesContentFolder}/data

#	Also sync the blog code
# !! Hardwired location
rsync -rtO --cvs-exclude ${server}:/websites/blog/content /websites/blog
# Resume exit on error
set -e

#	Latest routes
batchRoutes='www_routes_*.sql.gz'

#	Find all route files with the named pattern that have been modified within the last 24 hours.
files=$(ssh ${server} "find ${folder} -name '${batchRoutes}' -type f -mtime 0 -print")
for f in $files
do
    #	Get only the name component
    fileName=$(basename $f)

    #	Get the latest copy of www's current IJS tables.
    $download $administratorEmail $server $folder $fileName

    #	Add them
    gunzip < /websites/www/backups/$fileName | mysql -hlocalhost -uroot -p${mysqlRootPassword} cyclestreets
done

#
#	Repartition, which copies the current to the archived tables, and log output.
mysql cyclestreets -hlocalhost -uroot -p${mysqlRootPassword} -e "call repartitionIJS()" >> ${setupLogFile}

#	Discard route batch files that are exactly 7 days old
find ${folder} -name "${batchRoutes}" -type f -mtime 7 -delete
find ${folder} -name "${batchRoutes}.md5" -type f -mtime 7 -delete

#	CycleStreets Blog
$download $administratorEmail $server $folder www_schema_blog_database.sql.gz
mysql cyclestreets -hlocalhost -uroot -p${mysqlRootPassword} -e "drop database if exists blog;";
mysql cyclestreets -hlocalhost -uroot -p${mysqlRootPassword} -e "CREATE DATABASE blog DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci;";
gunzip < /websites/www/backups/www_schema_blog_database.sql.gz | mysql -hlocalhost -uroot -p${mysqlRootPassword} blog

#	Cyclescape Blog
$download $administratorEmail $server $folder www_schema_blogcyclescape_database.sql.gz
mysql cyclestreets -hlocalhost -uroot -p${mysqlRootPassword} -e "drop database if exists blogcyclescape;";
mysql cyclestreets -hlocalhost -uroot -p${mysqlRootPassword} -e "CREATE DATABASE blogcyclescape DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci;";
gunzip < /websites/www/backups/www_schema_blogcyclescape_database.sql.gz | mysql -hlocalhost -uroot -p${mysqlRootPassword} blogcyclescape


### Final Stage

# Finish
echo "$(date)	All done" >> ${setupLogFile}

# Remove the lock file - ${0##*/} extracts the script's basename
) 9>$lockdir/${0##*/}

# End of file
