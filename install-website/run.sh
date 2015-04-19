#!/bin/bash
# Script to install CycleStreets on Ubuntu
# Tested on 14.04.2 LTS Desktop (View Ubuntu version using 'lsb_release -a')
# This script is idempotent - it can be safely re-run without destroying existing data

# Announce start
echo "#	$(date)	CycleStreets installation"

# Ensure this script is run as root
if [ "$(id -u)" != "0" ]; then
    echo "#	This script must be run as root."
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

# Change to the script's folder
cd ${ScriptHome}

# Name of the credentials file
configFile=${ScriptHome}/.config.sh

# Generate your own credentials file by copying from .config.sh.template
if [ ! -x ${configFile} ]; then
    echo "#	The config file, ${configFile}, does not exist or is not executable - copy your own based on the ${configFile}.template file."
    exit 1
fi

# Load the credentials
. ${configFile}

# Load common install script
. ${ScriptHome}/utility/installCommon.sh

# Note: some new versions of php5.5 are missing json functions. This can be easily remedied by including the package: php5-json

# ImageMagick is used to provide enhanced maplet drawing. It is optional - if not present gd is used instead.
apt-get -y install imagemagick php5-imagick

# Apache/PHP performance packages (mod_deflate for Apache, APC cache for PHP)
sudo a2enmod deflate
apt-get -y install php-apc
/etc/init.d/apache2 restart

# Install Python
echo "#	Installing python"
apt-get -y install python php5-xmlrpc php5-curl

# Utilities
echo "#	Some utilities"
# ffmpeg has been removed from this line as not available (needed for translating videos uploaded to photomap)
# Install Apache mod_macro for convenience (not an actual requirement for CycleStreets)
apt-get -y install libapache2-mod-macro

# Install NTP to keep the clock correct (e.g. to avoid wrong GPS synchronisation timings)
apt-get -y install ntp

# These are used by deployment scripts to correspond with the routing servers via xml
apt-get -y install curl libxml-xpath-perl


# Geolocation by synchronization
# https://github.com/cyclestreets/cyclestreets/wiki/GPS-Syncronization
# For gpsPhoto.pl, add dependencies
apt-get -y install libimage-exiftool-perl
# This one might not actually be needed
apt-get -y install libxml-dom-perl
# Ensure the webserver (and group, but not others ideally) have executability on gpsPhoto.pl
chown www-data ${websitesContentFolder}/libraries/gpsPhoto.pl
chmod -x ${websitesContentFolder}/libraries/gpsPhoto.pl
chmod ug+x ${websitesContentFolder}/libraries/gpsPhoto.pl

# Select changelog
touch ${websitesContentFolder}/documentation/schema/selectChangeLog.sql
chown www-data:rollout ${websitesContentFolder}/documentation/schema/selectChangeLog.sql

# Requested missing cities logging (will disappear when ticket 645 cleared up)
touch ${websitesContentFolder}/documentation/RequestedMissingCities.tsv
chown www-data:rollout ${websitesContentFolder}/documentation/RequestedMissingCities.tsv

# Mod rewrite
a2enmod rewrite

# Virtual host configuration - for best compatibiliy use *.conf for the apache configuration files
cslocalconf=cyclestreets.conf
localVirtualHostFile=/etc/apache2/sites-available/${cslocalconf}

# Check if the local virtual host exists already
if [ ! -r ${localVirtualHostFile} ]; then
    # Create the local virtual host (avoid any backquotes in the text as they'll spawn sub-processes)
    cat > ${localVirtualHostFile} << EOF
<VirtualHost *:80>

	# Available URL(s)
	# Note: ServerName should not use wildcards, use ServerAlias for that.
	ServerName ${csServerName}

	# Logging
	CustomLog /websites/www/logs/access.log combined
	ErrorLog /websites/www/logs/error.log

	# Where the files are
	DocumentRoot /websites/www/content/
		
	# Include the application routing and configuration directives, loading it into memory rather than forcing per-hit rescans
	Include /websites/www/content/.htaccess-base
	Include /websites/www/content/.htaccess-cyclestreets

	# This is necessary to enable cookies to work on the domain http://localhost/
	# http://stackoverflow.com/questions/1134290/cookies-on-localhost-with-explicit-domain
	php_admin_value session.cookie_domain none

</VirtualHost>
EOF

    # Allow the user to edit this file
    chown ${username}:rollout ${localVirtualHostFile}

else
    echo "#	Virtual host already exists: ${localVirtualHostFile}"
fi

# Enable this virtual host
a2ensite ${cslocalconf}

# Add the api address to /etc/hosts if it is not already present
if ! cat /etc/hosts | grep "\b${apiServerName}\b" > /dev/null 2>&1
then

    # Start a list of aliases to add
    aliases=${apiServerName}

    # Unless localhost is being used, check cs server name
    if [ "${csServerName}" != "localhost" ]; then

	# If the servername is not present add an alias to localhost
	if  ! cat /etc/hosts | grep "\b${csServerName}\b" > /dev/null 2>&1
	then

	    # Add to aliases
	    aliases="${csServerName} ${aliases}"
	fi
    fi

    # Append
    echo "# Added by CycleStreets installation" >> /etc/hosts
    echo "127.0.1.1	${aliases}" >> /etc/hosts
fi

# Virtual host configuration - for best compatibiliy use *.conf for the apache configuration files
apilocalconf=api.cyclestreets.conf
apiLocalVirtualHostFile=/etc/apache2/sites-available/${apilocalconf}

# Check if the local virtual host exists already
if [ ! -r ${apiLocalVirtualHostFile} ]; then
    # Create the local virtual host (avoid any backquotes in the text as they'll spawn sub-processes)
    cat > ${apiLocalVirtualHostFile} << EOF
<VirtualHost *:80>

	ServerName ${apiServerName}
	
	# Logging
	CustomLog /websites/www/logs/${apiServerName}.access.log combined
	ErrorLog /websites/www/logs/${apiServerName}.error.log
	
	# Where the files are
	DocumentRoot /websites/www/content/
	
	# Include the application routing and configuration directives, loading it into memory rather than forcing per-hit
	Include /websites/www/content/.htaccess-base
	Include /websites/www/content/.htaccess-api
	
	# Development environment
	# Use MacroDevelopmentEnvironment '/'

</VirtualHost>
EOF

    # Allow the user to edit this file
    chown ${username}:rollout ${apiLocalVirtualHostFile}

else
    echo "#	Virtual host already exists: ${apiLocalVirtualHostFile}"
fi

# Enable this virtual host
a2ensite ${apilocalconf}



# Global conf file
zcsGlobalConf=zcsglobal.conf

# Determine location of apache global configuration files
if [ -d /etc/apache2/conf-available ]; then
    # Apache 2.4 location
    globalApacheConfigFile=/etc/apache2/conf-available/${zcsGlobalConf}
elif [ -d /etc/apache2/conf.d ]; then
    # Apache 2.2 location
    globalApacheConfigFile=/etc/apache2/conf.d/${zcsGlobalConf}
else
    echo "#	Could not decide where to put global virtual host configuration"
    exit 1
fi

echo "#	Setting global virtual host configuration in ${globalApacheConfigFile}"

# Check if the local global apache config file exists already
if [ ! -r ${globalApacheConfigFile} ]; then
    # Create the global apache config file
    cat > ${globalApacheConfigFile} << EOF
# Provides local configuration that affects all hosted sites.

# This file is loaded from the /etc/apache2/conf.d folder, it's name begins with a z so that it is loaded last from that folder.
# The files in the conf.d folder are all loaded before any VirtualHost files.

# Avoid giving away unnecessary information about the webserver configuration
ServerSignature Off
ServerTokens ProductOnly
php_admin_value expose_php 0

# ServerAdmin
ServerAdmin ${administratorEmail}

# PHP environment
php_value short_open_tag off

# Unicode UTF-8
AddDefaultCharset utf-8

# Disallow /somepage.php/Foo to load somepage.php
AcceptPathInfo Off

# Logging
LogLevel warn

# Statistics
Alias /images/statsicons /websites/configuration/analog/images

# Ensure FCKeditor .xml files have the correct MIME type
<Location /_fckeditor/>
	AddType application/xml .xml
</Location>

# Deny photomap file reading directly
<Directory /websites/www/content/data/photomap/>
	deny from all
</Directory>
<Directory /websites/www/content/data/photomap2/>
	deny from all
</Directory>
<Directory /websites/www/content/data/photomap3/>
	deny from all
</Directory>

# Disallow loading of .svn folder contents
<DirectoryMatch .*\.svn/.*>
	Deny From All
</DirectoryMatch>

# Deny access to areas not intended to be public
<LocationMatch ^/(archive|configuration|documentation|import|classes|libraries|scripts|routingengine)>
	order deny,allow
	deny from all
</LocationMatch>

# Disallow use of .htaccess file directives by default
<Directory />
	# Options FollowSymLinks
	AllowOverride None
	<IfModule mod_authz_core.c>
		Require all granted
	</IfModule>
</Directory>

EOF

    # Add IP bans - quoted to preserve newlines
    echo "${ipbans}" >> ${globalApacheConfigFile}
else
    echo "#	Global apache configuration file already exists: ${globalApacheConfigFile}"
fi

# Enable the configuration file (only necessary in Apache 2.4)
if [ -d /etc/apache2/conf-available ]; then
    a2enconf ${zcsGlobalConf}
fi

# Reload apache
/etc/init.d/apache2 reload

# Create cyclestreets database
${mysql} -e "create database if not exists cyclestreets default character set utf8 collate utf8_unicode_ci;"

# Users are created by the grant command if they do not exist, making these idem potent.
# The grant is relative to localhost as it will be the apache server that authenticates against the local mysql.
${mysql} -e "grant select, insert, update, delete, create, execute on cyclestreets.* to '${mysqlWebsiteUsername}'@'localhost' identified by '${mysqlWebsitePassword}';"
${mysql} -e "grant select, execute on \`routing%\` . * to '${mysqlWebsiteUsername}'@'localhost';"

# Allow the website to view any planetExtract files that have been created by an import
${mysql} -e "grant select on \`planetExtractOSM%\` . * to '${mysqlWebsiteUsername}'@'localhost';"

# Create the settings file if it doesn't exist
phpConfig=".config.php"
if [ ! -e ${websitesContentFolder}/${phpConfig} ]
then
    # Make a copy from the config template
    cp -p .config.php.template ${phpConfig}
fi

# Setup the configuration
if grep CONFIGURED_BY_HERE ${phpConfig} >/dev/null 2>&1;
then

    # Make the substitutions
    echo "#	Configuring the ${phpConfig}";
    sed -i \
-e "s|CONFIGURED_BY_HERE|Configured by cyclestreets-setup for csServerName: ${csServerName}${sourceConfig}|" \
-e "s/WEBSITE_USERNAME_HERE/${mysqlWebsiteUsername}/" \
-e "s/WEBSITE_PASSWORD_HERE/${mysqlWebsitePassword}/" \
-e "s/ADMIN_EMAIL_HERE/${administratorEmail}/" \
-e "s/YOUR_EMAIL_HERE/${mainEmail}/" \
-e "s/YOUR_SALT_HERE/${signinSalt}/" \
	${phpConfig}
fi


# Data

# Install a basic cyclestreets db from the repository
# Unless the cyclestreets db has already been loaded (check for presence of map_config table)
if ! ${mysql} --batch --skip-column-names -e "SHOW tables LIKE 'map_config'" cyclestreets | grep map_config  > /dev/null 2>&1
then
    # Load cyclestreets data
    echo "#	Load cyclestreets data"
    ${mysql} cyclestreets < ${websitesContentFolder}/documentation/schema/cyclestreetsSample.sql

    # Set the API server
    # Uses http rather than https as that will help get it working, then user can change later via the control panel.
    ${mysql} cyclestreets -e "update map_config set apiV2Url='http://${apiServerName}/v2/' where id = 1;"

    # Set the gui server
    # #!# This needs review - on one live machine it is set as localhost and always ignored
    ${mysql} cyclestreets -e "update map_gui set server='${csServerName}' where id = 1;"

    # Create an admin user
    encryption=`php -r"echo password_hash('${password}', PASSWORD_DEFAULT);"`
    ${mysql} cyclestreets -e "insert user_user (username, email, password, privileges, validatedAt, createdAt) values ('${username}', '${administratorEmail}', '${encryption}', 'administrator', NOW(), NOW());"

    # Create a welcome tinkle
    ${mysql} cyclestreets -e "insert tinkle (userId, tinkle) values (1, 'Welcome to CycleStreets');"
fi

# Archive db
archiveDb=csArchive
# Unless the database already exists:
if ! ${mysql} --batch --skip-column-names -e "SHOW DATABASES LIKE '${archiveDb}'" | grep ${archiveDb} > /dev/null 2>&1
then
    # Create archive database
    echo "#	Create ${archiveDb} database"
    ${mysql} < ${websitesContentFolder}/documentation/schema/csArchive.sql

    # Allow website read only access
    ${mysql} -e "grant select on \`${archiveDb}\` . * to '${mysqlWebsiteUsername}'@'localhost';"
fi

# External db
# This creates only a skeleton and sets up grant permissions. The full installation is done by a script in install-import folder.
# Unless the database already exists:
if [ -n "${externalDb}" ] && ! ${mysql} --batch --skip-column-names -e "SHOW DATABASES LIKE '${externalDb}'" | grep ${externalDb} > /dev/null 2>&1
then

    # Create external database
    echo "#	Create ${externalDb} database"
    echo "#	Note: this contains table definitions only and contains no data. A full version must be downloaded separately see ../install-import/run.sh"
    ${mysql} < ${websitesContentFolder}/documentation/schema/csExternal.sql

    # Allow website read only access
    ${mysql} -e "grant select on \`${externalDb}\` . * to '${mysqlWebsiteUsername}'@'localhost';"
fi

# External db restore
if [ -n "${externalDb}" -a -n "${csExternalDataFile}" -a ! -e ${websitesBackupsFolder}/${csExternalDataFile} ]; then

	# Report
	echo "#	$(date)	Starting download of external database"

	# Download
	wget http://cyclestreets:${datapassword}@data.cyclestreets.net/${csExternalDataFile} -O ${websitesBackupsFolder}/${csExternalDataFile}

	# Report
	echo "#	$(date)	Starting installation of external database"

	# Unpack into the skeleton db
	gunzip < ${websitesBackupsFolder}/${csExternalDataFile} | ${mysql} ${externalDb}

	# Remove the archive to save space
	# !! Can't remove as a reinstall would trigger another download.
	# rm ${websitesBackupsFolder}/${csExternalDataFile}

	# Report
	echo "#	$(date)	Completed installation of external database"
fi

# Batch db
# This creates only a skeleton and sets up grant permissions. A full installation is not yet available.
# Unless the database already exists:
if [ -n "${batchDb}" ] && ! ${mysql} --batch --skip-column-names -e "SHOW DATABASES LIKE '${batchDb}'" | grep ${batchDb} > /dev/null 2>&1 ; then

    # Create batch database
    echo "#	Create ${batchDb} database"
    ${mysql} -e "create database if not exists ${batchDb} default character set utf8 collate utf8_unicode_ci;"

    # Grants; note that the FILE privilege (which is not database-specific) is required so that table contents can be loaded from a file
    ${mysql} -e "GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, DROP, INDEX, LOCK TABLES on \`${batchDb}\` . * to '${mysqlWebsiteUsername}'@'localhost';"
    ${mysql} -e "GRANT FILE ON *.* TO '${mysqlWebsiteUsername}'@'localhost';"

    echo "#	Note: this contains table definitions only and contains no data."
    ${mysql} < ${websitesContentFolder}/documentation/schema/csBatch.sql

else
    echo "#	Skipping batch database"
fi

# Identify the sample database (the -s suppresses the tabular output)
sampleRoutingDb=$(${mysql} -s cyclestreets<<<"select routingDb from map_config limit 1")
echo "#	The sample database is: ${sampleRoutingDb}"

# Unless the sample routing database already exists:
if ! ${mysql} --batch --skip-column-names -e "SHOW DATABASES LIKE '${sampleRoutingDb}'" | grep ${sampleRoutingDb} > /dev/null 2>&1
then
    # Create sampleRoutingDb database
    echo "#	Create ${sampleRoutingDb} database"
    ${mysql} -e "create database if not exists ${sampleRoutingDb} default character set utf8 collate utf8_unicode_ci;"

    # Load data
    echo "#	Load ${sampleRoutingDb} data"
    gunzip < ${websitesContentFolder}/documentation/schema/routingSample.sql.gz | ${mysql} ${sampleRoutingDb}
fi

# Unless the sample routing data exists:
if [ ! -d ${websitesContentFolder}/data/routing/${sampleRoutingDb} ]; then
    echo "#	Unpacking ${sampleRoutingDb} data"
    tar xf ${websitesContentFolder}/documentation/schema/routingSampleData.tar.gz -C ${websitesContentFolder}/data/routing
fi


# Create a config if not already present
if [ ! -x "${routingEngineConfigFile}" ]; then
	# Create the config for the basic routing db, as cyclestreets user
	${asCS} touch "${routingEngineConfigFile}"
	${asCS} echo -e "#!/bin/bash\nBASEDIR=${websitesContentFolder}/data/routing/${sampleRoutingDb}" > "${routingEngineConfigFile}"
	# Ensure it is executable
	chmod a+x "${routingEngineConfigFile}"
fi

# Compile the C++ module; see: https://github.com/cyclestreets/cyclestreets/wiki/Python-routing---starting-and-monitoring
sudo apt-get -y install gcc g++ python-dev
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
if $configureExim ; then
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
    sudo /etc/init.d/exim4 restart
fi

# Install the cycle routing daemon (service)
if $installRoutingAsDaemon ; then

    # Setup a symlink from the etc init demons folder, if it doesn't already exist
    if [ ! -L ${routingDaemonLocation} ]; then
	ln -s ${websitesContentFolder}/routingengine/cyclerouting.init.d ${routingDaemonLocation}
    fi

    # Ensure the relevant files are executable
    chmod ug+x ${websitesContentFolder}/routingengine/cyclerouting.init.d
    chmod ug+x ${websitesContentFolder}/routingengine/routing_server.py

    # Start the service
    # Acutally uses the restart option, which is more idempotent
    ${routingDaemonLocation} restart
    echo -e "\n# Follow the routing log using: tail -f ${websitesLogsFolder}/pythonAstarPort9000.log"

    # Add the daemon to the system initialization, so that it will start on reboot
    update-rc.d cycleroutingd defaults

else

    echo "#	Routing service - (not installed as a daemon)"
    echo "#	Can be manually started from the command line using:"
    echo "#	sudo -u cyclestreets ${websitesContentFolder}/routingengine/routing_server.py"

    # If it was previously setup as a daemon, remove it
    if [ -L ${routingDaemonLocation} ]; then

	# Ensure it is stopped
	${routingDaemonLocation} stop

	# Remove the symlink
	rm ${routingDaemonLocation}

	# Remove the daemon from the system initialization
	update-rc.d cycleroutingd remove
    fi

fi



# Advise setting up
if [ "${csServerName}" != "localhost" ]; then
    echo "#	Ensure ${csServerName} routes to this machine, eg by adding this line to /etc/hosts"
    echo "127.0.0.1	${csServerName} api.${csServerName}"
fi

# Announce end of script
echo "#	CycleStreets installed $(date), visit http://${csServerName}/"

# Return true to indicate success
:

# End of file
