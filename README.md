# cyclestreets-setup

Scripts for installing CycleStreets, developing for Ubuntu 14.04.2 LTS

**Note this is work-in-progress and the CycleStreets repo which is needed is not yet publicly available.**

## Requirements

Tested, March 2015 on a Ubuntu Server 14.04.2 LTS VM with 1 GB RAM, 8GB HD.


## Setup

Add this repository to a machine using the following, as your normal username (not root). In the listing the grouped items can usually be cut and pasted together into the command shell, others require responding to a prompt:

    cd ~
    sudo apt-get -y install git

    git clone https://github.com/cyclestreets/cyclestreets-setup.git

    sudo mv cyclestreets-setup /opt
    cd /opt/cyclestreets-setup/
    git config core.sharedRepository group

    sudo adduser --gecos "" cyclestreets

    sudo addgroup rollout

    # Some command shells won't detect the preceding group change, so reset your shell eg. by logging out and then back in again
    sudo chown -R cyclestreets.rollout /opt/cyclestreets-setup

    sudo chmod -R g+w /opt/cyclestreets-setup
    sudo find /opt/cyclestreets-setup -type d -exec chmod g+s {} \;


## Install website

After the repository has been cloned from Github above, proceed by making your own */opt/cyclestreets-setup.config.sh* file based on the */opt/cyclestreets-setup.config.sh.template* file.

Provide a password for the subversion repository for your username, ie *repopassword* in the config file. By default the script will try the same password as provided for the cyclestreteets user.

The *root* user is required to install the packages, but most of the installation is done as the *cyclestreets* user (using *sudo*).

    cyclestreets@machine:/opt/cyclestreets-setup/install-website$ sudo ./run.sh


## Use

Once the script has run you should be able to go to:

    http://localhost/

    or

    http://*csServerName*/

to see the CycleStreets home page.

## Troubleshooting

Check apache2 logs in `/websites/www/logs/` or `/var/log/apache2/`.

If you've chosen a *csServerName* other than *localhost* make sure it routes to the server, eg by adding a line to /etc/hosts
