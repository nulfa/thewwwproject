#!/bin/bash

cd

#
# fix locales
#
echo "en_US.UTF-8 UTF-8" > /var/lib/locales/supported.d/local
dpkg-reconfigure locales

#
# we don't need samba and it's kinda big
#
apt-get -y remove samba samba-common

#
# get up to date
#
apt-get update && apt-get -y upgrade

#
# need these for next steps
#
apt-get -y install curl apg

#
# install mysql, set mysql root pass
#

#
# sadly, I have to deal with this in case the downloads
# fail
#
apt-get -y remove --purge mysql-server
rm -rf /etc/mysql

MYSQL_PASS=`/usr/bin/apg -n 1 -m 10 -x 10`
echo "mysql-server mysql-server/root_password select $MYSQL_PASS" | debconf-set-selections
echo "mysql-server mysql-server/root_password_again select $MYSQL_PASS" | debconf-set-selections

apt-get -y install mysql-server

#
# make a .my.cnf file for sanity's sake
#
cat <<EOF > /root/.my.cnf
[client]
user=root
password=$MYSQL_PASS

EOF

chmod 600 /root/.my.cnf

#
# install needed php
#
apt-get -y install php5-cgi php5-mysql php5-curl php5-gd php5-imagick php-apc php5-cli php-pear

#
# defaults file for php-fastcgi
#
cat <<EOF > /etc/default/php-fastcgi
#
# Settings for php-cgi in external FASTCGI Mode
#

# Should php-fastcgi run automatically on startup? (default: no)

START=yes

# Which user runs PHP? (default: www-data)

EXEC_AS_USER=wordpress

# Socket location

FCGI_SOCKET_DIR=/tmp
FCGI_SOCKET=php-socket

# Environment variables, which are processed by PHP

PHP_FCGI_CHILDREN=32
PHP_FCGI_MAX_REQUESTS=1000

EOF

#
# Now the init script for php-fastcgi
#
cat <<EOF > /etc/init.d/php-fastcgi
#! /bin/sh
### BEGIN INIT INFO
# Provides:          php-fastcgi
# Required-Start:    \$all
# Required-Stop:     \$all
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Start and stop php-cgi in external FASTCGI mode
# Description:       Start and stop php-cgi in external FASTCGI mode
### END INIT INFO

# Author: Kurt Zankl <[EMAIL PROTECTED]>
# Modified: Chris Lea http://chrislea.com

# Do NOT "set -e"

PATH=/sbin:/usr/sbin:/bin:/usr/bin
DESC="php-cgi in external FASTCGI mode"
NAME=php-fastcgi
DAEMON=/usr/bin/php-cgi
PIDFILE=/var/run/\$NAME.pid
SCRIPTNAME=/etc/init.d/\$NAME

# Exit if the package is not installed
[ -x "\$DAEMON" ] || exit 0

# Read configuration variable file if it is present
[ -r /etc/default/\$NAME ] && . /etc/default/\$NAME

# Load the VERBOSE setting and other rcS variables
. /lib/init/vars.sh

# Define LSB log_* functions.
# Depend on lsb-base (>= 3.0-6) to ensure that this file is present.
. /lib/lsb/init-functions

# If the daemon is not enabled, give the user a warning and then exit,
# unless we are stopping the daemon
if [ "\$START" != "yes" -a "\$1" != "stop" ]; then
        log_warning_msg "To enable \$NAME, edit /etc/default/\$NAME and set 
START=yes"
        exit 0
fi

# Process configuration
export PHP_FCGI_CHILDREN PHP_FCGI_MAX_REQUESTS
DAEMON_ARGS="-q -b \$FCGI_SOCKET_DIR/\$FCGI_SOCKET"

do_start()
{
        # Return
        #   0 if daemon has been started
        #   1 if daemon was already running
        #   2 if daemon could not be started
        start-stop-daemon --start --quiet --pidfile \$PIDFILE --exec \$DAEMON --test > /dev/null \
                || return 1
        start-stop-daemon --start --quiet --pidfile \$PIDFILE --exec \$DAEMON \
                --background --make-pidfile --chuid \$EXEC_AS_USER --startas \$DAEMON -- \
                \$DAEMON_ARGS \
                || return 2
}

do_stop()
{
        # Return
        #   0 if daemon has been stopped
        #   1 if daemon was already stopped
        #   2 if daemon could not be stopped
        #   other if a failure occurred
        start-stop-daemon --stop --quiet --retry=TERM/30/KILL/5 --pidfile \$PIDFILE > /dev/null # --name \$DAEMON
        RETVAL="\$?"
        [ "\$RETVAL" = 2 ] && return 2
        # Wait for children to finish too if this is a daemon that forks
        # and if the daemon is only ever run from this initscript.
        # If the above conditions are not satisfied then add some other code
        # that waits for the process to drop all resources that could be
        # needed by services started subsequently.  A last resort is to
        # sleep for some time.
        start-stop-daemon --stop --quiet --oknodo --retry=0/30/KILL/5 --exec \$DAEMON
        [ "\$?" = 2 ] && return 2
        # Many daemons don't delete their pidfiles when they exit.
        rm -f \$PIDFILE
        return "\$RETVAL"
}

case "\$1" in
  start)
        [ "\$VERBOSE" != no ] && log_daemon_msg "Starting \$DESC" "\$NAME"
        do_start
        case "\$?" in
                0|1) [ "\$VERBOSE" != no ] && log_end_msg 0 ;;
                2) [ "\$VERBOSE" != no ] && log_end_msg 1 ;;
        esac
        ;;
  stop)
        [ "\$VERBOSE" != no ] && log_daemon_msg "Stopping \$DESC" "\$NAME"
        do_stop
        case "\$?" in
                0|1) [ "\$VERBOSE" != no ] && log_end_msg 0 ;;
                2) [ "\$VERBOSE" != no ] && log_end_msg 1 ;;
        esac

        ;;
  restart|force-reload)
        log_daemon_msg "Restarting \$DESC" "\$NAME"
        do_stop
        case "\$?" in
          0|1)
                do_start
                case "\$?" in
                        0) log_end_msg 0 ;;
                        1) log_end_msg 1 ;; # Old process is still running
                        *) log_end_msg 1 ;; # Failed to start
                esac
                ;;
          *)
                # Failed to stop
                log_end_msg 1
                ;;
        esac
        ;;
  *)
        echo "Usage: \$SCRIPTNAME {start|stop|restart|force-reload}" >&2
        exit 3
        ;;
esac

EOF

#
# create WordPress user
#
SALT=`/usr/bin/apg -n 1 -x 2 -m 2`
WP_USER_PASS=`/usr/bin/apg -n 1 -x 10 -m 10`
WP_USER_PASS_CRYPT=`perl -e "print crypt('$WP_USER_PASS','$SALT');"`

useradd -m --password $WP_USER_PASS_CRYPT wordpress

#
# start php fastcgi processes
#
chmod 755 /etc/init.d/php-fastcgi
/etc/init.d/php-fastcgi start
update-rc.d php-fastcgi defaults


#
# create home directory for WordPress install
#
/bin/mkdir -p -v /var/www/$HOSTNAME

#
# Svn checkout of current version into web root
#
apt-get -y install subversion
svn co http://svn.automattic.com/wordpress/tags/5.8/ /var/www/$HOSTNAME/

#
# permissions
#
chown -R wordpress: /var/www/$HOSTNAME

#
# create database for WordPress
#
mysql -e "CREATE DATABASE wordpress"
mysql -e "GRANT ALL PRIVILEGES ON wordpress.* to wordpress@localhost IDENTIFIED BY '$WP_USER_PASS'"
mysql -e "FLUSH PRIVILEGES"

#
# Install postfix
#
echo "postfix postfix/mailname string $HOSTNAME" | debconf-set-selections
echo "postfix postfix/main_mailer_type select Internet Site" | debconf-set-selections
apt-get -y install postfix

#
# Install nginx
#
apt-get -y install nginx

#
# and configure it
#
perl -p -i -e 's|www-data|wordpress|g;' /etc/nginx/nginx.conf

cat <<EOF > /etc/nginx/sites-available/$HOSTNAME.conf
server {
    listen 80;
    server_name $HOSTNAME www.$HOSTNAME;


    if ( \$host = www.$HOSTNAME ) {
        rewrite ^\/(.*)\$ http://$HOSTNAME/\$1 permanent;
    }
    access_log /var/log/nginx/$HOSTNAME-access.log;

    location ~ /\.svn/* {
        deny all;
    }

    location ~ \.ht* {
        deny all;
    }

    location / {
        root /var/www/$HOSTNAME;
        index index.php index.html;

        charset UTF-8;
        gzip    on;
        gzip_comp_level 2;
        gzip_vary   on;
        gzip_proxied    any;
        gzip_types text/plain text/xml text/css application/x-javascript;

        if (-f \$request_filename) {
            break;
        }

        set \$supercache_file '';
        set \$supercache_uri \$request_uri;

        if (\$request_method = POST) {
            set \$supercache_uri '';
        }

        if (\$query_string) {
            set \$supercache_uri '';
        }

        if (\$http_cookie ~* "comment_author_|wordpress|wp-postpass_" ) {
            set \$supercache_uri '';
        }

        if (\$supercache_uri ~ ^(.+)\$) {
            set \$supercache_file /wp-content/cache/supercache/\$http_host/\$1index.html;
        }

        if (-f \$document_root\$supercache_file) {
            rewrite ^(.*)\$ \$supercache_file break;
        }

        if (!-e \$request_filename) {
            rewrite . /index.php last;
        }

    }

    location ~ \.(jpg|jpeg|png|gif|ico)\$ {
        root /var/www/$HOSTNAME;
        expires 7d;
    }

    error_page 404 = /index.php?q=\$request_uri;

    location ~ \.php\$ {
        fastcgi_pass    unix:/tmp/php-socket;
        fastcgi_index   index.php;
        fastcgi_param SCRIPT_FILENAME /var/www/$HOSTNAME\$fastcgi_script_name;
        include         fastcgi_params;
    }

}

EOF

#
# install munin and set it up
#
apt-get -y install munin munin-node
cd /etc/munin/plugins
rm -fv ./*
for i in cpu df df_inode entropy forks interrupts load memory open_files \
         open_inodes postfix_mailqueue postfix_mailvolume processes vmstat \
         mysql_queries mysql_slowqueries mysql_bytes mysql_threads; \
         do ln -s -v /usr/share/munin/plugins/$i . ; done

ln -s -v /usr/share/munin/plugins/if_ if_venet0

/etc/init.d/munin-node restart

#
# configure nginx for munin too
#
echo "wordpress:$WP_USER_PASS_CRYPT" > /etc/nginx/htpasswd

cat <<EOF > /etc/nginx/sites-available/munin.conf
server {
    listen 7131;
    server_name $HOSTNAME www.$HOSTNAME;

    if ( \$host = www.$HOSTNAME ) {
        rewrite ~\/(.*)\$ http://$HOSTNAME/\$1 permanent;
    }

    access_log /var/log/nginx/munin.$HOSTNAME-access.log;

    location / {
        root /var/www/munin;
        index index.html index.htm;
        auth_basic "Authorization Required";
        auth_basic_user_file htpasswd;
    }

    error_page 404 /404.html;

    error_page 500 502 503 504 /50x.html;
    location = /50x.html {
        root /var/www/nginx-default;
    }
}

EOF

#
# finish nginx config
#
cd /etc/nginx/sites-enabled
rm -fv default
ln -s -v ../sites-available/$HOSTNAME.conf 001-$HOSTNAME.conf
ln -s -v ../sites-available/munin.conf 002-munin.conf
/etc/init.d/nginx restart

#
# configure WordPress itself
#
cd /var/www/$HOSTNAME
perl -p -i -e "s|putyourdbnamehere|wordpress|;" wp-config-sample.php
perl -p -i -e "s|usernamehere|wordpress|;" wp-config-sample.php
perl -p -i -e "s|yourpasswordhere|$WP_USER_PASS|;" wp-config-sample.php
mv wp-config-sample.php wp-config.php

#
# friendly finishing up message for the user
#

echo ""
echo ""
echo ""
echo "########################################################################"
echo "########################################################################"
echo "########################################################################"
echo ""
echo "Hi! We've installed WordPress for you. You have the currently newest"
echo "version which is $WP_VERSION."
echo ""
echo "There are some things to be aware of. First is that everything is running"
echo "as the 'WordPress' user. If that doesn't mean a lot to you, don't worry."
echo "Practically, it's just saying that things like WordPress upgrades will work"
echo "smoothly from inside the WordPress admin area."
echo ""
echo "If you need to, you can ssh or sftp into this server as the WordPress user"
echo "using the following password:"
echo ""
echo "$WP_USER_PASS"
echo ""
echo "Requests to http://www.$HOSTNAME will automagically be redirected to:"
echo ""
echo "http://$HOSTNAME"
echo ""
echo "If you want to see graphs of how your server is doing, you can do so here:"
echo ""
echo "http://$HOSTNAME:7131"
echo ""
echo "This is password protected with the username WordPress and the password"
echo "listed above. It may take a few more minutes before you can get there,"
echo "since there's not any data to graph just yet."
echo ""
echo "IMPORTANT: This server is configured to make use of the wp-super-cache"
echo "WordPress plugin. You can and should install this plugin as it will let your"
echo "blog handle vastly more traffic than it otherwise could. You can install it"
echo "very easily from the WordPress admin with the following steps:"
echo ""
echo "1) Log into the WordPress admin."
echo "2) Click on Plugins, then Add New, then search for wp-super-cache."
echo "3) When it comes up, click the links to install it."
echo "4) Be sure to enable it, turn it on, and then enable Super Cache Compression."
echo "5) Ignore warnings about mod_rewrite or writable directories, they don't apply."
echo ""
echo "Enjoy http://$HOSTNAME !"
echo ""