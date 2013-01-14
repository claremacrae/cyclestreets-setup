#!/bin/bash
# Script to install CycleStreets on Ubuntu
# Tested on 12.10 (View Ubuntu version using 'lsb_release -a')
# This script is idempotent - it can be safely re-run without destroying existing data

echo "#	CycleStreets installation $(date)"

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

# Name of the credentials file
configFile=../.config.sh

# Generate your own credentials file by copying from .config.sh.template
if [ ! -e ./${configFile} ]; then
    echo "#	The config file, ${configFile}, does not exist - copy your own based on the ${configFile}.template file." 1>&2
    exit 1
fi

# Load the credentials
. ./${configFile}

# Logging
# Use an absolute path for the log file to be tolerant of the changing working directory in this script
setupLogFile=$SCRIPTDIRECTORY/log.txt
touch ${setupLogFile}
echo "#	CycleStreets installation in progress, follow log file with: tail -f ${setupLogFile}"
echo "#	CycleStreets installation $(date)" >> ${setupLogFile}

# Ensure there is a cyclestreets user account
if id -u ${username} >/dev/null 2>&1; then
    echo "#	User ${username} exists already and will be used."
else
    echo "#\User ${username} does not exist: creating now."

    # Request a password for the CycleStreets user account; see http://stackoverflow.com/questions/3980668/how-to-get-a-password-from-a-shell-script-without-echoing
    if [ ! ${password} ]; then
	stty -echo
	printf "Please enter a password that will be used to create the CycleStreets user account:"
	read password
	printf "\n"
	printf "Confirm that password:"
	read passwordconfirm
	printf "\n"
	stty echo
	if [ $password != $passwordconfirm ]; then
	    echo "#	The passwords did not match"
	    exit 1
	fi
    fi

    # Create the CycleStreets user
    useradd -m $username >> ${setupLogFile}
    # Assign the password - this technique hides it from process listings
    echo "${username}:${password}" | /usr/sbin/chpasswd
    echo "#	CycleStreets user ${username} created" >> ${setupLogFile}
fi

# Add the user to the sudo group, if they are not already present
if ! groups ${username} | grep "\bsudo\b" > /dev/null 2>&1
then
    adduser ${username} sudo
fi

# Shortcut for running commands as the cyclestreets user
asCS="sudo -u ${username}"

# Install basic software
apt-get -y install wget git emacs >> ${setupLogFile}

# Install Apache, PHP
echo "#	Installing Apache, MySQL, PHP" >> ${setupLogFile}

# Provide the mysql root password - to avoid being prompted.
echo mysql-server mysql-server/root_password password ${mysqlRootPassword} | debconf-set-selections
echo mysql-server mysql-server/root_password_again password ${mysqlRootPassword} | debconf-set-selections

# Install core webserver software
apt-get -y install apache2 mysql-server mysql-client php5 php5-gd php5-cli php5-mysql >> ${setupLogFile}

# Apache/PHP performance packages (mod_deflate for Apache, APC cache for PHP)
sudo a2enmod deflate
apt-get -y install php-apc
service apache2 restart

# Install Python
echo "#	Installing python" >> ${setupLogFile}
apt-get -y install python php5-xmlrpc php5-curl >> ${setupLogFile}

# Utilities
echo "#	Some utilities" >> ${setupLogFile}
apt-get -y install subversion openjdk-6-jre bzip2 ffmpeg >> ${setupLogFile}

# Install NTP to keep the clock correct (e.g. to avoid wrong GPS synchronisation timings)
apt-get -y install ntp

# This package prompts for configuration, and so is left out of this script as it is only a developer tool which can be installed later.
# apt-get -y install phpmyadmin

# Determine the current actual user
currentActualUser=`who am i | awk '{print $1}'`

# Create the rollout group, if it does not already exist
if ! grep -i "^rollout\b" /etc/group > /dev/null 2>&1
then
    addgroup rollout
fi

# Add the user to the rollout group, if not already there
if ! groups ${username} | grep "\brollout\b" > /dev/null 2>&1
then
	usermod -a -G rollout ${username}
fi

# Add the person installing the software to the rollout group, for convenience, if not already there
if ! groups ${currentActualUser} | grep "\brollout\b" > /dev/null 2>&1
then
	usermod -a -G rollout ${currentActualUser}
fi

# Working directory
mkdir -p /websites

# Set the group for the containing folder to be rollout:
chown ${username}:rollout /websites

# Allow sharing of private groups
umask 0002

# This is the clever bit which adds the setgid bit, it relies on the value of umask.
# It means that all files and folders that are descendants of this folder recursively inherit its group, ie. rollout.
chmod g+ws /websites

# Add the path to content (the -p option creates the intermediate www)
mkdir -p ${websitesContentFolder}

# Create a folder for Apache to log access / errors:
mkdir -p ${websitesLogsFolder}

# Create a folder for backups
mkdir -p ${websitesBackupsFolder}

# Switch to content folder
cd ${websitesContentFolder}

# Create/update the CycleStreets repository, ensuring that the files are owned by the CycleStreets user (but the checkout should use the current user's account - see http://stackoverflow.com/a/4597929/180733 )
if [ ! -d ${websitesContentFolder}/.svn ]
then
    ${asCS} svn co --username=${currentActualUser} --no-auth-cache http://svn.cyclestreets.net/cyclestreets ${websitesContentFolder} >> ${setupLogFile}
else
    ${asCS} svn update --username=${currentActualUser} --no-auth-cache
fi

# Allow the Apache webserver process to write / add to the data/ folder
chown -R www-data ${websitesContentFolder}/data

# For gpsPhoto.pl (for geolocation by synchronization), add dependencies, and Ensure the webserver (and group, but not others ideally) have executability on gpsPhoto.pl
apt-get -y install libimage-exiftool-perl
apt-get -y install libxml-dom-perl		# Might not actually be needed
chown www-data ${websitesContentFolder}/scripts/gpsPhoto.pl
chmod -x ${websitesContentFolder}/scripts/gpsPhoto.pl
chmod ug+x ${websitesContentFolder}/scripts/gpsPhoto.pl

# Blog must be able to upload content, and to upgrade make it group-writable for the rollout group
chown -R www-data:rollout ${websitesContentFolder}/blog
chmod -R g+w ${websitesContentFolder}/blog

# Select changelog
touch ${websitesContentFolder}/documentation/schema/selectChangeLog.sql
chown www-data:rollout ${websitesContentFolder}/documentation/schema/selectChangeLog.sql

# Requested missing cities logging (will disappear when ticket 645 cleared up)
touch ${websitesContentFolder}/documentation/RequestedMissingCities.tsv
chown www-data:rollout ${websitesContentFolder}/documentation/RequestedMissingCities.tsv

# Mod rewrite
a2enmod rewrite >> ${setupLogFile}

# Virtual host configuration
# Create symbolic link if it doesn't already exist
if [ ! -L /etc/apache2/sites-available/cslocalhost ]; then
    ln -s ${websitesContentFolder}/configuration/apache/sites-available/cslocalhost /etc/apache2/sites-available/
fi
a2ensite cslocalhost >> ${setupLogFile}

# Add apache2/conf.d/ files such as zcsglobal
if [ ! -L /etc/apache2/conf.d/zcsglobal ]; then
    #	Include zcsglobal config which is so named as to be loaded last from the conf.d folder.
    ln -s ${websitesContentFolder}/configuration/apache/conf.d/zcsglobal /etc/apache2/conf.d/zcsglobal
fi

# Reload apache
service apache2 reload >> ${setupLogFile}


# Database setup
# Useful binding
mysql="mysql -uroot -p${mysqlRootPassword} -hlocalhost"

# Create cyclestreets database
${mysql} -e "create database if not exists cyclestreets default character set utf8 collate utf8_unicode_ci;" >> ${setupLogFile}

# Users are created by the grant command if they do not exist, making these idem potent.
# The grant is relative to localhost as it will be the apache server that authenticates against the local mysql.
${mysql} -e "grant select, insert, update, delete, execute on cyclestreets.* to '${mysqlWebsiteUsername}'@'localhost' identified by '${mysqlWebsitePassword}';" >> ${setupLogFile}
${mysql} -e "grant select, execute on \`routing%\` . * to '${mysqlWebsiteUsername}'@'localhost' identified by '${mysqlWebsitePassword}';" >> ${setupLogFile}

# Update-able blogs
${mysql} -e "grant select, insert, update, delete, execute on \`blog%\` . * to '${mysqlWebsiteUsername}'@'localhost' identified by '${mysqlWebsitePassword}';" >> ${setupLogFile}

# The following is needed only to support OSM import
${mysql} -e "grant select on \`planetExtractOSM%\` . * to '${mysqlWebsiteUsername}'@'localhost';" >> ${setupLogFile}

# Create the settings file if it doesn't exist
phpConfig=".config.php"
if [ ! -e ${websitesContentFolder}/${phpConfig} ]
then
    cp .config.php.template ${phpConfig}
fi

# Setup the config?
if grep WEBSITE_USERNAME_HERE ${phpConfig} >/dev/null 2>&1;
then

    # Make the substitutions
    echo "#	Configuring the ${phpConfig}";
    sed -i \
-e "s/WEBSITE_USERNAME_HERE/${mysqlWebsiteUsername}/" \
-e "s/WEBSITE_PASSWORD_HERE/${mysqlWebsitePassword}/" \
-e "s/YOUR_EMAIL_HERE/${administratorEmail}/" \
-e "s/YOUR_EMAIL_HERE/${mainEmail}/" \
	${phpConfig}
fi


# Data

# Install a basic cyclestreets db from the repository
# Unless the cyclestreets db has already been loaded (check for presence of map_config table)
if ! ${mysql} --batch --skip-column-names -e "SHOW tables LIKE 'map_config'" cyclestreets | grep map_config  > /dev/null 2>&1
then
    # Load cyclestreets data
    echo "#	Load cyclestreets data"
    gunzip < ${websitesContentFolder}/documentation/schema/cyclestreets.sql.gz | ${mysql} cyclestreets >> ${setupLogFile}
fi

# Install a basic routing db from the repository
# Unless the database already exists:
if ! ${mysql} --batch --skip-column-names -e "SHOW DATABASES LIKE 'routing121114'" | grep routing121114 > /dev/null 2>&1
then
    # Create routing121114 database
    echo "#	Create routing121114 database"
    ${mysql} -e "create database if not exists routing121114 default character set utf8 collate utf8_unicode_ci;" >> ${setupLogFile}

    # Load data
    echo "#	Load routing121114 data"
    gunzip < ${websitesContentFolder}/documentation/schema/routing121114.sql.gz | ${mysql} routing121114 >> ${setupLogFile}
fi

# Setup a symlink to the routing data if it doesn't already exist
if [ ! -L ${websitesContentFolder}/data/routing/current ]; then
    ln -s routing121114 ${websitesContentFolder}/data/routing/current
fi

# Compile the C++ module; see: https://github.com/cyclestreets/cyclestreets/wiki/Python-routing---starting-and-monitoring
sudo apt-get -y install gcc g++ python-dev >> ${setupLogFile}
if [ ! -e ${websitesContentFolder}/routingengine/astar_impl.so ]; then
	echo "Now building the C++ routing module..."
	cd "${websitesContentFolder}/routingengine/"
	${asCS} python setup.py build
	${asCS} mv build/lib.*/astar_impl.so ./
	${asCS} rm -rf build/
	cd ${websitesContentFolder}
fi

# Add this python module which is needed by the routing_server.py script
sudo apt-get -y install python-argparse

# Add Exim, so that mail will be sent, and add its configuration, but firstly backing up the original exim distribution config file if not already done
# NB The config here is currently Debian/Ubuntu-specific
sudo apt-get -y install exim4
if [ ! -e /etc/exim4/update-exim4.conf.conf.original ]; then
	cp -pr /etc/exim4/update-exim4.conf.conf /etc/exim4/update-exim4.conf.conf.original
fi
# NB These will deliberately overwrite any existing config; it is assumed that once set, the config will only be changed via this setup script (as otherwise it is painful during testing)
sed -i "s/dc_eximconfig_configtype=.*/dc_eximconfig_configtype='${dc_eximconfig_configtype}'/" /etc/exim4/update-exim4.conf.conf
sed -i "s/dc_local_interfaces=.*/dc_local_interfaces='${dc_local_interfaces}'/" /etc/exim4/update-exim4.conf.conf
sed -i "s/dc_readhost=.*/dc_readhost='${dc_readhost}'/" /etc/exim4/update-exim4.conf.conf
sed -i "s/dc_smarthost=.*/dc_smarthost='${dc_smarthost}'/" /etc/exim4/update-exim4.conf.conf
# NB These two are the same in any CycleStreets installation but different from the default Debian installation:
sed -i "s/dc_other_hostnames=.*/dc_other_hostnames=''/" /etc/exim4/update-exim4.conf.conf
sed -i "s/dc_hide_mailname=.*/dc_hide_mailname='true'/" /etc/exim4/update-exim4.conf.conf
sudo service exim4 restart

# Install the cycle routing daemon (service)
# It can also be manually started from the command line (ideally within a screen session) using:
# sudo -u cyclestreets ${websitesContentFolder}/routingengine/routing_server.py

# Setup a symlink from the etc init demons folder, if it doesn't already exist
if [ ! -L /etc/init.d/cycleroutingd ]; then
    ln -s ${websitesContentFolder}/routingengine/cyclerouting.init.d /etc/init.d/cycleroutingd
fi
# Ensure the relevant files are executable
chmod ug+x ${websitesContentFolder}/routingengine/cyclerouting.init.d
chmod ug+x ${websitesContentFolder}/routingengine/routing_server.py

# Start the service
# Acutally uses the restart option, which is more idempotent
service cycleroutingd restart
echo -e "\n# Follow the routing log using: tail -f ${websitesLogsFolder}/pythonAstarPort9000.log"

# Add the daemon to the system initialization, so that it will start on reboot
update-rc.d cycleroutingd defaults

# Cron jobs
if $installCronJobs ; then

    # Install the cron job here
    echo "#	Install cron jobs"

    # Daily replication every day at 4:04 am
    jobs[1]="4 4 * * * $SCRIPTDIRECTORY/../replicate-data/run.sh"

    # Hourly zapping at 13 mins past every hour
    jobs[2]="13 * * * * $SCRIPTDIRECTORY/../remove-tempgenerated/run.sh"

    # Install routing data at 34 mins past every hour in the small hours
    jobs[3]="34 0,1,2,3,4,5 * * * $SCRIPTDIRECTORY/../install-routing-data/run.sh"

    for job in "${jobs[@]}"
    do
	# Check the format which should be 5 timings followed by the script each separated by a single space
	[[ ! $job =~ ^([^' ']+' '){5}([^' ']+)$ ]] && echo "# Crontab intallation incorrect job format (m h dom mon dow usercommand) for: $job" && exit 1

	# Fish out the command which is the last component of the match
	command="${BASH_REMATCH[2]}"

	# Install/update the job
	# frgrep -v .. <(${} crontab -l) filters out any previous occurrences from the user's crontab listing
	# The echo adds the new job and the cat | pipes it to set the user's updated crontab
	cat <(fgrep -i -v "$command" <(${asCS} crontab -l)) <(echo "$job") | ${asCS} crontab -

	# Installed
	echo "#	Cron: $job"
    done

else

    # Remove the cron job here
    echo "#	Remove any installed cron jobs"
    ${asCS} crontab -r

fi

# Confirm end of script
echo -e "#	All now installed $(date)"
