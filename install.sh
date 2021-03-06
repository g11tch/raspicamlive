#! /bin/bash


#============================================================================================#
## Simple installer for the raspicam live
#============================================================================================#


# Move current directory to project / install directory
cd $(readlink -f $( dirname "${BASH_SOURCE[0]}" ))

# Include utilities and own library

source "install/utilities.sh"
source "install/lib.sh"

if [ ! -f "install/config.sh" ] ; then
    cp "install/config.sh.dist" "install/config.sh"
fi;
source "install/config.sh"

## Performs checks

# Raw functions
crash(){ echo $1; exit 1; }
raw_apt(){ dpkg-query -s "$1" 2>/dev/null 1>/dev/null; [ 0 -eq $? ] || apt-get install -y "$1"; }

# check_path
[ "$(pwd)" == "/usr/local/lib/raspicamlive" ] || crash "You must install this package in /usr/local/lib/raspicamlive. Exiting."

# check_is_root
[ "root" == "$( whoami )" ] || crash "You must run this script as root. Exiting."


# check_has_net
ping -c 1 -W 1 google.com 2>/dev/null >/dev/null
RESULT=$?; 
[ 0 -eq $RESULT ] || crash "You must have internet access. Exiting."

# check aptitude update

# @todo

# Gettext is a hard dependancy, install it "raw style"
raw_apt gettext


# Firmware update
info "Updating the firmware"
rpi-update > /dev/null

# Immediately rsync this package /etc templates 
[ -d $TMP_PATH ] || mkdir -p  $TMP_PATH
rsync -a "$APP_PATH/etc" "$TMP_PATH" > /dev/null

[ $? -eq 0 ] || alert "Could not rsync the configuration files."

## Configure aptitude

# Refresh
info "Refreshing apt cache"
apt-get update > /dev/null

# required packages
apt_get sudo
apt_get avahi-daemon
apt_get lsb-release
apt_get rsync
apt_get apache2-mpm-prefork
apt_get libapache2-mod-php5
apt_get php5-cli
apt_get screen
apt_get ffmpeg
apt_get libass-dev
apt_get libasound2-dev
apt_get libavcodec-extra
apt_get libfdk-aac-dev
apt_get libmp3lame-dev
apt_get libvpx-dev
apt_get libx264-dev

## Check group rights

# www-data needs to be a member of the video group
usermod -G video www-data

## Configure disk
PI_STORAGE="/mnt"
info "Checking USB disk presence"
ls /dev/sda1 2>/dev/null 1>/dev/null
if [ $? -ne 0 ] ; then 
    warn "No disk found"

# Partitioning disk if required
else 
    PARTITION_TYPE=$(file -sL /dev/sda1 | sed -r 's/^(.*?)(ext[2-4])(.*?)$/\2/g')
    if [ -z "$PARTITION_TYPE" ] ; then 
        ask "Your USB disk is not valid. Would you like to format it now? [Y/n]"
        warn "This will remove all the data available on the disk."
        read DO_FORMAT
        case $DO_FORMAT in
            [Nn] ) ;;
            *)
                format_usb "/dev/sda1"
            ;;
        esac
    fi
fi

# Automount
grep "^/dev/sda1" /etc/fstab 2>/dev/null >/dev/null
if [ $? -ne 0 ] ; then

    ask "Do you want your usb drive to be automatically mounted in /mnt? [Y/n]"
    read DO_MOUNT
    case $DO_MOUNT in
        [Nn] ) ;;
        *)
            edit_fstab "/dev/sda1"
        ;;
    esac
fi

# Remount all disks
mount -a

# Check USB disk is mounted, readable, etc.
MOUNTED=$(mount | grep "/mnt")
if [ -z "$MOUNTED" ] ; then 
    warn "Your USB disk does not seem to mounted."
else 

    MOUNT_FLAGS_RW=$(echo $MOUNTED | awk '{print $6}'|grep "rw" >/dev/null)
    [ $? -eq 0 ] || warn "Your USB disk is not mounted Read/Write. Troubles ahead."

fi

# Ensure the /mnt/current directory exist
[ -d "/mnt/current" ] || mkdir "/mnt/current"
[ $? -eq 0 ] || warn "Could not create the /mnt/current directory. Troubles ahead."

# Ensure the log directory exists
[ -d "/var/log/raspicam" ] || { mkdir /var/log/raspicam && chown www-data:www-data /var/log/raspicam ; }

## Configure sudoers
copy "$TMP_PATH/etc/sudoers.d/raspicamlive" /etc/sudoers.d/

## Configure PI network name
PI_NAME="raspilive01"
spacer
misc "You will use the following "Network Name" to reach the website of the raspberry Pi." 
misc "For example, a pi named 'mylive' will be locally accessible on http://mylive.local" 
spacer
ask "Please give your RaspberryPi Network Name (Default: raspilive01): "
read REPLY_PI_NAME
[ -z $REPLY_PI_NAME ] || PI_NAME=$REPLY_PI_NAME
replace "%PI_NAME%" "$PI_NAME" "$TMP_PATH/etc/hostname"
copy "$TMP_PATH/etc/hostname" "/etc/hostname"

## Configure avahi

replace "%PI_NAME%" "$PI_NAME" "$TMP_PATH/etc/avahi/avahi-daemon.conf"
copy "$TMP_PATH/etc/avahi/avahi-daemon.conf" /etc/avahi/avahi-daemon.conf
service avahi-daemon restart


## Configure apache

# Disable the default website
a2dissite default

# Make sure the files are owned by the server
chown -R www-data: "${APP_PATH}/www"
copy "${TMP_PATH}/etc/apache2/sites-available/raspicamlive" /etc/apache2/sites-available/raspicamlive

# Enable the site
a2ensite raspicamlive

# Restart Apache
service apache2 restart

## Configure daemon
copy "$TMP_PATH/etc/init.d/streamer-daemon" "/etc/init.d/streamer-daemon"
chmod 700  "/etc/init.d/streamer-daemon"
update-rc.d streamer-daemon defaults
/etc/init.d/streamer-daemon start


info "Install completed. You will reach the application on http://${PI_NAME}.local"

# Reboot
spacer
ask "You should now reboot the Raspberry Pi. Reboot now? [Y/n]"
read REBOOT
case $REBOOT in
    [Nn] ) ;;
    *) reboot;;
esac
 
