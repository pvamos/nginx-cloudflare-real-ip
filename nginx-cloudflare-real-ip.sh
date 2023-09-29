#!/bin/tcsh -f
#
# /usr/local/bin/nginx-cloudflare-real-ip.sh
#
# Create (and if necessary update) includable nginx config file snippet
# containing real_ip_header set_real_ip_from nginx directives
# for Cloudflare IPv4 and IPv6 lists.
# restart nginx if needed, only after succesful test of configuration.
# Log every relevant events of operation with details to log file.
#
# Forked and main concept from Bash version of Ergin BULUT
#   https://github.com/ergin/nginx-cloudflare-real-ip
#
# 
# https://github.com/pvamos/nginx-cloudflare-real-ip
# by Péter Vámos
#   pvamos@gmail.com
#   https://linkedin.com/in/pvamos
#
# - ported to FreeBSD tcsh
# - checks validating Cloudflare IPv4 or IPv6 lists received
# - previous update state storage in files
# - checks to update config (and restart nginx) only if really necessary (the published Cloudflare IP lists has chaged)
# - backing up nginx config in /tmp/cloudflare_backup_{tcsh PID}_{Unix time stamp},
#     rollback without restart, if nginx configuration test fails
# - added detailed logging, (also including nginx logs if nginx config change fails),
# - all possible operating scenarios lead to defined operation with logged outcome
# - log rotation configuration
#

set LOGFILE='/var/log/nginx-cloudflare-real-ip.log'
# unique temp file to store nginx config test output:
# /tmp/nginx_conftest_{tcsh PID}_{Unix time stamp}
set TEST_TEMP_FILE="/tmp/nginx_conftest_$$_`date +%s`"
# main output file containing real_ip_header set_real_ip_from nginx directives for Cloudflare source IPs
set CLOUDFLARE_FILE_PATH='/usr/local/etc/nginx/cloudflare'
# backup /tmp/cloudflare_backup_{tcsh PID}_{Unix time stamp}
set CLOUDFLARE_FILE_PATH_ORIG='/tmp/cloudflare_backup_$$_`date +%s'
set CLOUDFLARE_LASTV4_PATH='/usr/local/etc/nginx/ips-v4'
set CLOUDFLARE_LASTV6_PATH='/usr/local/etc/nginx/ips-v6'

# get the current Cloudflare IPv4 and IPv6 lists
set CLOUDFLARE_IPS_V4="`/usr/local/bin/curl -s -L https://www.cloudflare.com/ips-v4`"
set CLOUDFLARE_IPS_V6="`/usr/local/bin/curl -s -L https://www.cloudflare.com/ips-v6`"
# get the last used Cloudflare IPv4 and IPv6 lists
set CLOUDFLARE_IPS_V4_LAST="`/bin/cat $CLOUDFLARE_LASTV4_PATH`"
set CLOUDFLARE_IPS_V6_LAST="`/bin/cat $CLOUDFLARE_LASTV6_PATH`"

# the current IPv4 and IPv6 lists we got are "valid" (longer than 20 characters)
if (`echo $CLOUDFLARE_IPS_V4 | /usr/bin/wc -c | /usr/bin/tr -d ' '` > 20 && `echo $CLOUDFLARE_IPS_V6 | /usr/bin/wc -c | /usr/bin/tr -d ' '` > 20) then

    # Cloudflare IPv4 or IPv6 list changed since last run
    if (("$CLOUDFLARE_IPS_V4" != "$CLOUDFLARE_IPS_V4_LAST") || ("$CLOUDFLARE_IPS_V4" != "$CLOUDFLARE_IPS_V4_LAST")) then

        # backup original Cloudflare IP-s file
        /bin/cp $CLOUDFLARE_FILE_PATH $CLOUDFLARE_FILE_PATH_ORIG

        # re-write Cloudflare IP-s file with current IPv4 and IPv6 lists
        echo "#Cloudflare" > $CLOUDFLARE_FILE_PATH;
        echo "" >> $CLOUDFLARE_FILE_PATH;

        echo "# - IPv4" >> $CLOUDFLARE_FILE_PATH;
        foreach i ($CLOUDFLARE_IPS_V4)
            echo "set_real_ip_from $i;" >> $CLOUDFLARE_FILE_PATH;
        end

        echo "" >> $CLOUDFLARE_FILE_PATH;
        echo "# - IPv6" >> $CLOUDFLARE_FILE_PATH;
        foreach i ($CLOUDFLARE_IPS_V6)
            echo "set_real_ip_from $i;" >> $CLOUDFLARE_FILE_PATH;
        end

        echo "" >> $CLOUDFLARE_FILE_PATH;
        echo "real_ip_header CF-Connecting-IP;" >> $CLOUDFLARE_FILE_PATH;

        # test nginx configuration
        /usr/local/sbin/nginx -t -q >& "$TEST_TEMP_FILE"

        # nginx configuration check was successful
        if ("$?" == 0) then

            /usr/sbin/service nginx reload >&/dev/null

            # save currently used Cloudflare IPv4 and IPv6 lists
            echo $CLOUDFLARE_IPS_V4 > $CLOUDFLARE_LASTV4_PATH;
            echo $CLOUDFLARE_IPS_V6 > $CLOUDFLARE_LASTV6_PATH;

            echo "`/bin/date -u +'%Y-%m-%d %H:%M:%S UTC'` - nginx-cloudflare-real-ip - Cloudflare IPv4 or IPv6 list changed, nginx config check successful, nginx restarted with new config" >> $LOGFILE

            # delete nginx config backup and test temp file
            /bin/rm "$CLOUDFLARE_FILE_PATH_ORIG"
			/bin/rm "$TEST_TEMP_FILE"

        else

            # nginx configuration check failed, restore original Cloudflare IP-s file from backup
            /bin/cp $CLOUDFLARE_FILE_PATH_ORIG $CLOUDFLARE_FILE_PATH

            # remove newlines from nginx config test temp file
            /bin/cat "$TEST_TEMP_FILE" | /usr/bin/tr '\n' ' ' | tee "$TEST_TEMP_FILE" >/dev/null
            echo "`/bin/date -u +'%Y-%m-%d %H:%M:%S UTC'` - nginx-cloudflare-real-ip - Cloudflare IPv4 or IPv6 list changed, nginx config check failed, nginx config rolled back without restart - `/bin/cat "$TEST_TEMP_FILE"`" >> $LOGFILE

            # delete nginx config backup and test temp file
            /bin/rm "$CLOUDFLARE_FILE_PATH_ORIG"
			/bin/rm "$TEST_TEMP_FILE"

        endif

    else

        # Cloudflare IPv4 and IPv6 lists did not change
        echo "`/bin/date -u +'%Y-%m-%d %H:%M:%S UTC'` - nginx-cloudflare-real-ip - Cloudflare IPv4 and IPv6 list did not change, keeping original nginx config" >> $LOGFILE

    endif

else

    # at least one of IPv4 and IPv6 lists is shorter than 20
    echo "`/bin/date -u +'%Y-%m-%d %H:%M:%S UTC'` - nginx-cloudflare-real-ip - Cloudflare IPv4 or IPv6 list invalid, keeping original nginx config" >> $LOGFILE

endif
