#!/bin/bash
OUTPUT=/var/www/html/mrtg/mrtg.tmp
SNMPRO=public

echo "WorkDir: /var/www/html/mrtg
Options[_]: bits
Forks: 8
SnmpOptions: retries => 2, timeout => 1
LogFormat: rrdtool
PathAdd: /usr/bin/
14all*columns: 3" > $OUTPUT

IPHOSTS=`grep -E "mrtg" /etc/xymon/hosts.cfg | awk '{print $2}'`
for HOST in $IPHOSTS
do
#	cfgmaker --subdirs=$HOST --snmp-options=:161:2:2:1:2 --ifdesc=descr --ifref=descr --host-template=host.template --if-template=interface-errors.template --output=$HOST.tmp $SNMPRO@$HOST 2> /dev/null
	cfgmaker --subdirs=$HOST --snmp-options=:161:2:2:1:2 --ifdesc=descr --ifref=descr --output=$HOST.tmp $SNMPRO@$HOST 2> /dev/null
	if [ ! -e /var/www/html/mrtg/$HOST ]; then
	        mkdir /var/www/html/mrtg/$HOST
        fi
	if [ ! -e /var/www/html/mrtg/$HOST/14all.cgi ]; then
		cp 14all.cgi /var/www/html/mrtg/$HOST/
	fi
	echo "WorkDir: ." > /var/www/html/mrtg/$HOST/mrtg.cfg
	echo "Options[_]: bits" >> /var/www/html/mrtg/$HOST/mrtg.cfg
	grep -Ev "WorkDir|Directory" $HOST.tmp >> /var/www/html/mrtg/$HOST/mrtg.cfg
	grep -v WorkDir $HOST.tmp >> $OUTPUT
	rm $HOST.tmp
done

mv $OUTPUT /var/www/html/mrtg/mrtg.cfg
