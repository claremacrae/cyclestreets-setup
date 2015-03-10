# cyclestreets-setup

Scripts for installing CycleStreets, developing for Ubuntu 12.10 / Debian Squeeze

**Note this is work-in-progress and the CycleStreets repo which is needed is not yet publicly available.**

After the repository has been cloned from Github (see instructions below), proceed by making your own *.config.sh* file based on the *.config.sh.template* file.

The *root* user is required to install the packages, but most of the installation is done as the *cyclestreets* user (using *sudo*).

    cyclestreets@machine:/opt/cyclestreets-setup/install-website$ sudo ./run.sh

With apache 2.4 there's a line to uncomment in `/etc/apache2/conf-available/zcsglobal.conf`

## Use

Once the script has run you should be able to go to:

http://localhost/

to see the CycleStreets home page.

## Troubleshooting

Check apache2 logs in `/websites/www/logs/` or `/var/log/apache2/`.


## Setup

Add this repository to a machine using the following, as your normal username (not root):

    cd ~
    sudo apt-get -y install git
    git clone https://github.com/cyclestreets/cyclestreets-setup.git
    sudo mv cyclestreets-setup /opt
    cd /opt/cyclestreets-setup/
    git config core.sharedRepository group
    sudo adduser cyclestreets
    sudo addgroup rollout
    sudo chown -R cyclestreets.rollout /opt/cyclestreets-setup
    sudo chmod g+s /opt/cyclestreets-setup
