# Get the origin client IP behind Cloudflare for Nginx, using a cronjob to keep config up to date

Forked from and main concept from Linux / Bash version of [Ergin BULUT](https://github.com/ergin) https://github.com/ergin/nginx-cloudflare-real-ip

Ported to FreeBSD / tcsh by [Péter Vámos](https://github.com/pvamos) https://github.com/pvamos/nginx-cloudflare-real-ip

Simple `tcsh` script to create and update an includable nginx config file snippet containing `real_ip_header` `set_real_ip_from` nginx directives for source IPv4 and IPv6 lists published by Cloudflare:

- https://www.cloudflare.com/ips-v4
- https://www.cloudflare.com/ips-v6

Cloudflare's reverse proxy network adds the `CF-Connecting-IP` header. https://developers.cloudflare.com/fundamentals/reference/http-request-headers/#cf-connecting-ip

Nginx's `ngx_http_realip_module` module is used to change the client address and optional port to those sent in the specified header field. http://nginx.org/en/docs/http/ngx_http_realip_module.html

Tested with FreeBSD 13.2-RELEASE on AMD64 architecture, with tcsh 6.22.04, with nginx 1.24.0_6,3 running inside a BSD Jail. Tested scenarios:
- Traffic arriving through Cloudflare's reverse proxy network, nginx acts as a reverse proxy, forwarding requests to backend.
- Traffic arriving through Cloudflare's reverse proxy network, nginx serves content directly.

## Differences from the original I've forked from
- ported to FreeBSD tcsh
- checks validating Cloudflare IPv4 or IPv6 lists received
- previous update state storage in files
- checks to update config (and restart nginx) only if really necessary (the published Cloudflare IP lists has chaged)
- backing up nginx config in /tmp/cloudflare_backup_{tcsh PID}_{Unix time stamp}, rollback without restart, if nginx configuration test fails
- added detailed logging, (also including nginx logs if nginx config test fails)
- all possible operating scenarios lead to defined operation with logged outcome
- log rotation configuration

## Nginx Configuration
We are inserting a configuration snippet to the nginx configuration file with `include`:

```nginx
include /usr/local/etc/nginx/cloudflare;
```

The configuration snippet is like:
```nginx
#Cloudflare

# - IPv4
set_real_ip_from 173.245.48.0/20;
set_real_ip_from 103.21.244.0/22;
set_real_ip_from 103.22.200.0/22;
set_real_ip_from 103.31.4.0/22;
set_real_ip_from 141.101.64.0/18;
set_real_ip_from 108.162.192.0/18;
set_real_ip_from 190.93.240.0/20;
set_real_ip_from 188.114.96.0/20;
set_real_ip_from 197.234.240.0/22;
set_real_ip_from 198.41.128.0/17;
set_real_ip_from 162.158.0.0/15;
set_real_ip_from 104.16.0.0/13;
set_real_ip_from 104.24.0.0/14;
set_real_ip_from 172.64.0.0/13;
set_real_ip_from 131.0.72.0/22;

# - IPv6
set_real_ip_from 2400:cb00::/32;
set_real_ip_from 2606:4700::/32;
set_real_ip_from 2803:f800::/32;
set_real_ip_from 2405:b500::/32;
set_real_ip_from 2405:8100::/32;
set_real_ip_from 2a06:98c0::/29;
set_real_ip_from 2c0f:f248::/32;

real_ip_header CF-Connecting-IP;
```
We are adding the snippet to the nginx condfiguration like below. On my FreeBSD the nginx config file is at `/usr/local/etc/nginx/nginx.conf`.

```nginx
http {
        server {
                listen 443 ssl;
                server_name host1.example.net;
...
                # Proxy target
                location / {
                        root /usr/local/www/host1.example.net;
...
                        include /usr/local/etc/nginx/cloudflare;
                }
        }
        server {
                listen 443 ssl;
                server_name host2.example.net;
...
                # Proxy target
                location / {
                        proxy_pass http://[backend]:80$request_uri;
...
                        include /usr/local/etc/nginx/cloudflare;
                }
        }
}
```

## Crontab
The script is intended to run periodcally with a crontab similar to:
```sh
# /etc/cron.d/nginx-cloudflare-real-ip
#
# Create (and if necessary update) includable nginx config file snippet
# containing real_ip_header set_real_ip_from nginx directives
# for Cloudflare IPv4 and IPv6 lists
# restart nginx if needed, only after succesful test of configuration.
# Log every relevant events of operation with details to log file.
#

SHELL=/bin/tcsh
PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin:/root/bin

# check hourly, at 45 minutes past the hour
30     *       *       *       *       root    /usr/local/bin/nginx-cloudflare-real-ip.sh >&/dev/null
```

## Log rotation
We can configure log rotation with `newsyslog` like:
```sh
# $FreeBSD$
# /etc/newsyslog.conf.d/nginx-cloudflare-real-ip.conf
# logfilename                         [owner:group] mode count size when flags [/pid_file] [sig_num]
/var/log/nginx-cloudflare-real-ip.log root:wheel    644  20    2048 *    JC
```

## Log example
```sh
...
2023-09-28 16:30:04 UTC - nginx-cloudflare-real-ip - Cloudflare IPv4 and IPv6 list did not change, keeping original nginx config
2023-09-28 17:30:03 UTC - nginx-cloudflare-real-ip - Cloudflare IPv4 and IPv6 list did not change, keeping original nginx config
# To simulate Cloudflare changing the published IPv4 and IPv6 list contents,
# I've changed the Cloudflare IPv4 and IPv6 lists saved at previous 17:30 run,
# And to test an nginx config rollback due to config check fail,
# I've added "asdsada" to the 3rd line of /usr/local/etc/nginx/nginx.conf
2023-09-28 17:34:11 UTC - nginx-cloudflare-real-ip - Cloudflare IPv4 or IPv6 list changed, nginx config check failed, nginx config rolled back original without restart - nginx: [emerg] unknown directive "asdsada" in /usr/local/etc/nginx/nginx.conf:3 nginx: configuration file /usr/local/etc/nginx/nginx.conf test failed
# I've removed "asdsada" from the 3rd line of /usr/local/etc/nginx/nginx.conf
2023-09-28 17:38:23 UTC - nginx-cloudflare-real-ip - Cloudflare IPv4 or IPv6 list changed, nginx config check successful, nginx restarted with new config
2023-09-28 18:30:04 UTC - nginx-cloudflare-real-ip - Cloudflare IPv4 and IPv6 list did not change, keeping original nginx config
2023-09-28 19:30:02 UTC - nginx-cloudflare-real-ip - Cloudflare IPv4 and IPv6 list did not change, keeping original nginx config
...
```

## The actual script
```sh
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
# - added detailed logging, (also including nginx logs if nginx config test fails),
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
```

### License

[Apache 2.0](http://www.apache.org/licenses/LICENSE-2.0)


### DISCLAIMER
----------
Please note: all tools/ scripts in this repo are released for use "AS IS" **without any warranties of any kind**,
including, but not limited to their installation, use, or performance.  We disclaim any and all warranties, either 
express or implied, including but not limited to any warranty of noninfringement, merchantability, and/ or fitness 
for a particular purpose.  We do not warrant that the technology will meet your requirements, that the operation 
thereof will be uninterrupted or error-free, or that any errors will be corrected.

Any use of these scripts and tools is **at your own risk**.  There is no guarantee that they have been through 
thorough testing in a comparable environment and we are not responsible for any damage or data loss incurred with 
their use.

You are responsible for reviewing and testing any scripts you run *thoroughly* before use in any non-testing 
environment.
