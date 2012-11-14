#!/bin/bash
# Script to install CycleStreets on Ubuntu
# Tested on 12.04 (View Ubuntu version using 'lsb_release -a') using Postgres 9.1
# http://wiki.openstreetmap.org/wiki/Nominatim/Installation#Ubuntu.2FDebian

echo "#	CycleStreets installation $(date)"

# Ensure this script is run as root
if [ "$(id -u)" != "0" ]; then
    echo "#	This script must be run as root." 1>&2
    exit 1
fi

# Bomb out if something goes wrong
set -e

### CREDENTIALS ###
# Name of the credentials file
configFile=.config.sh

# Generate your own credentials file by copying from .config.sh.template
if [ ! -e ./${configFile} ]; then
    echo "#	The config file, ${configFile}, does not exist - copy your own based on the ${configFile}.template file." 1>&2
    exit 1
fi

# Load the credentials
. ./${configFile}

# Logging
# Use an absolute path for the log file to be tolerant of the changing working directory in this script
setupLogFile=$(readlink -e $(dirname $0))/setupLog.txt
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
    echo $password | passwd $username --stdin
    echo "#	CycleStreets user ${username} created" >> ${setupLogFile}
fi

# Check whether the user is alredy in the sudo group
if ! groups ${username} | grep "\bsudo\b" > /dev/null 2>&1
then
    # Add the user to it
    adduser ${username} sudo
fi


# Shortcut for running commands as the cyclestreets users
asCS="sudo -u ${username}"

# Install basic software
apt-get -y install wget git emacs >> ${setupLogFile}

# Install Apache, PHP
echo "#	Installing Apache, MySQL, PHP" >> ${setupLogFile}

# Provide the mysql root password - to avoid being prompted.
echo mysql-server mysql-server/root_password password ${mysqlRootPassword} | debconf-set-selections
echo mysql-server mysql-server/root_password_again password ${mysqlRootPassword} | debconf-set-selections

apt-get -y install apache2 mysql-server mysql-client php5 php5-gd php5-cli php5-mysql >> ${setupLogFile}

# Install Python
echo "#	Installing python" >> ${setupLogFile}
apt-get -y install python php5-xmlrpc php5-curl >> ${setupLogFile}

# Utilities
echo "#	Some utilities" >> ${setupLogFile}
apt-get -y install subversion openjdk-6-jre bzip2 ffmpeg >> ${setupLogFile}

# This package prompts for configuration, and so is left out of this script as it is only a developer tool which can be installed later.
# apt-get -y install phpmyadmin

#   ___
# /     \
# |  1  | 
# |     |
# -------
# Milestone 1
echo "# Reached milestone 1"

# Check if the rollout group exists
if ! grep -i "^rollout\b" /etc/group > /dev/null 2>&1
then

    # Create the roll out group
    addgroup rollout

fi

# Check whether the user is alredy in the rollout group
if ! groups ${username} | grep "\brollout\b" > /dev/null 2>&1
then
    # Add the user to it
    adduser ${username} rollout
fi

# Working directory
mkdir -p /websites

# Set the group for the containing folder to be rollout:
chown ${username}:rollout /websites

# Allow sharing of private groups
umask 0002

# This is the clever bit which adds the setgid bit, it relies on the value of umask.
# It means that all files and folders that are descendants of this folder recursively inherit it's group, ie. rollout.
chmod g+ws /websites

# Add the path to content (the -p option creates the intermediate www)
mkdir -p ${websitesContentFolder}

# Create a folder for Apache to log access / errors:
mkdir -p ${websitesLogsFolder}

# Create a folder for backups
mkdir -p ${websitesBackupsFolder}

# Switch to content folder
cd ${websitesContentFolder}

# Check if the repository has been created
if [ ! -d ${websitesContentFolder}/.svn ]
then
    # Populate with source code by checking out from the CycleStreets repository:
    ${asCS} svn co http://svn.cyclestreets.net/cyclestreets ${websitesContentFolder} >> ${setupLogFile}
fi

# Setup the permissions
configuration/permissions.sh 

# Mod rewrite
a2enmod rewrite >> ${setupLogFile}

# Virtual host configuration
# Create symbolic link if it doesn't already exist
if [ ! -L /etc/apache2/sites-available/cslocalhost ]; then
    ln -s ${websitesContentFolder}/configuration/apache/sites-available/cslocalhost /etc/apache2/sites-available/
fi
a2ensite cslocalhost >> ${setupLogFile}

# Reload apache
service apache2 reload >> ${setupLogFile}

#   ___
# /     \
# |  2  | 
# |     |
# -------
# Milestone 2
echo "# Reached milestone 2"

# Database setup
# Shortcut
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

# Configure the settings file
phpConfig=".config.php"
if [ ! -e ${websitesContentFolder}/${phpConfig} ]
then

    # Instantiate from the template
    cp .config.php.template ${phpConfig}

    # Make it executable
    chmod a+x ${phpConfig}
fi

# Setup the config?
if grep WEBSITE_USERNAME_HERE ${phpConfig} >/dev/null 2>&1;
then

    # Make the substitutions
    echo "#	Configuring the ${phpConfig}";
    sed -i \
-e "s/[#]*\$config\['username'] = 'WEBSITE_USERNAME_HERE';/\$config\['username'] = '${mysqlWebsiteUsername}';/" \
-e "s/[#]*\$config\['password'] = 'WEBSITE_PASSWORD_HERE';/\$config\['password'] = '${mysqlWebsitePassword}';/" \
-e "s/[#]*\$config\['administratorEmail'] = 'YOUR_EMAIL_HERE';/\$config\['administratorEmail'] = '${administratorEmail}';/" \
-e "s/[#]*\$config\['mainEmail'] = 'YOUR_EMAIL_HERE';/\$config\['mainEmail'] = '${mainEmail}';/" \
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
echo "#	The routing service can be started from the command line via: cyclestreets@${websitesContentFolder}\$ python classes/routing_server.py"

# Narrate the end of script
echo "# Reached end of installation script"
