#!/bin/bash
# Script to deploy CycleStreets dev server on Ubuntu
# Tested on 14.04 (View Ubuntu version using 'lsb_release -a')
# This script is idempotent - it can be safely re-run without destroying existing data

echo "#	CycleStreets Dev machine deployment $(date)"

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

# Use this to remove the ../
ScriptHome=$(readlink -f "${DIR}/..")

# Name of the credentials file
configFile=${ScriptHome}/.config.sh

# Generate your own credentials file by copying from .config.sh.template
if [ ! -x ${configFile} ]; then
    echo "#	The config file, ${configFile}, does not exist or is not excutable - copy your own based on the ${configFile}.template file." 1>&2
    exit 1
fi

# Load the credentials
. ${configFile}

# Check a base OS has been defined
if [ -z "${baseOS}" ]; then
	echo "#     Please define a value for baseOS in the config file."
	exit 1
fi
echo "# Installing CycleStreets website for base OS: ${baseOS}"

# Install a base webserver machine with webserver software (Apache, PHP, MySQL), relevant users and main directory
. ${ScriptHome}/utility/installBaseWebserver.sh

# Enable mod_ssl for HTTPS sites
a2enmod ssl
service apache2 reload

# Load helper functions
. ${ScriptHome}/utility/helper.sh

# Install a base webserver machine with webserver software (Apache, PHP, MySQL), relevant users and main directory
. ${ScriptHome}/utility/installBaseWebserver.sh

# Add mod_macro to help simplify Apache configuration
apt-get -y install libapache2-mod-macro
a2enmod macro

# Update scripts daily at 6:25am
installCronJob ${username} "25 6 * * * cd ${ScriptHome} && git pull -q"

# Backup data every day at 6:26am
installCronJob ${username} "26 6 * * * ${ScriptHome}/dev-deployment/dailybackup.sh"

# Enable SMS site monitoring, every 5 minutes
installCronJob ${username} "0,5,10,15,20,25,30,35,40,45,50,55 * * * * php ${ScriptHome}/sms-monitoring/run.php"


# Confirm end of script
echo -e "#	All now deployed $(date)"

# End of file
