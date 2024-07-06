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

IPHOSTS=`grep -E "\-IS0|\-RT0|\-CR0|\-FW0|mrtg" /etc/xymon/hosts.cfg | awk '{print $2}'`
for HOST in $IPHOSTS
do
	HOSTNAME=`grep $HOST /etc/xymon/hosts.cfg | awk '{print $2}'`
	HOSTTYPE=`snmpget -t1 -r1 -Oqv -v1 -c $SNMPRO $HOST .1.3.6.1.2.1.1.1.0 2> /dev/null`
	if [ "$HOSTTYPE" = "" ]
	then
		HOSTPING=`ping -W1 -c1 $HOST 2> /dev/null | grep "1 received"`
		if [ "$HOSTPING" = "" ]
		then
			echo "Cannot ping host $HOST!"
		else
			echo "SNMP is not working on host $HOST.  Skipping..."
		fi
		continue
	else
		if [[ $HOSTTYPE = *NetApp* ]]
		then
			cfgmaker --subdirs=$HOST --host-template=host-netapp-filer.template.txt --nointerfaces --output=$HOST.tmp $SNMPRO@$HOST 2> /dev/null
		elif [[ $HOSTTYPE = *APC* ]]
		then
			cfgmaker --subdirs=$HOST --host-template=host-pdu.template --nointerfaces --output=$HOST.tmp $SNMPRO@$HOST 2> /dev/null
			echo $HOST >> APCHOST.lst
		elif [[ $HOSTTYPE = *MELLANOX* ]]
		then
			echo "Running Mellanox because $HOST is $HOSTTYPE"
			cfgmaker --subdirs=$HOST --snmp-options=:161:1:1:1:1 --ifdesc=alias --host-template=host.template --output=$HOST.tmp $SNMPRO@$HOST 2> /dev/null
		elif [[ $HOST = *F50* ]]
		then
			echo "Running F5 because $HOST is F5"
			/root/cfgmaker/f5lb-cfgmaker.pl d1str1but10n@$HOST > $HOST.tmp
#		elif [[ $HOSTTYPE = *Linux* ]]
#                then
#			echo "Running Linux because $HOST is $HOSTTYPE"
#                        cfgmaker --subdirs=$HOST --snmp-options=:161:1:1:1:1 --host-template=host.template --ifref=descr --output=$HOST.tmp $SNMPRO@$HOST 2> /dev/null
		elif [[ $HOSTTYPE = *HP* ]] || [[ $HOSTTYPE = *Arista** ]] || [[ $HOSTTYPE = *Force10* ]] || [[ $HOSTTYPE = *ProCurve* ]] || [[ $HOSTTYPE = *Mellanox* ]]
		then
			echo "Running HP on $HOSTNAME"	
			cfgmaker --subdirs=$HOST --snmp-options=:161:2:2:1:2 --ifdesc=descr --ifref=descr --host-template=host.template --if-template=interface-errors.template --output=$HOST.tmp $SNMPRO@$HOST 2> /dev/null
		else
			echo "Running DEFAULT on $HOSTNAME"
			cfgmaker --subdirs=$HOST --snmp-options=:161:2:2:1:1 --ifdesc=alias --ifref=descr --if-template=interface-errors.template --output=$HOST.tmp $SNMPRO@$HOST 2> /dev/null
		fi
	fi
	if [ ! -e /var/www/html/mrtg/$HOSTNAME ]
        then
	        mkdir /var/www/html/mrtg/$HOSTNAME
        fi
	if [ ! -e /var/www/html/mrtg/$HOSTNAME/14all.cgi ]
	then
		cp 14all.cgi /var/www/html/mrtg/$HOSTNAME/
	fi
	echo "WorkDir: ." > /var/www/html/mrtg/$HOSTNAME/mrtg.cfg
	echo "Options[_]: bits" >> /var/www/html/mrtg/$HOSTNAME/mrtg.cfg
	grep -Ev "WorkDir|Directory" $HOST.tmp >> /var/www/html/mrtg/$HOSTNAME/mrtg.cfg
	grep -v WorkDir $HOST.tmp >> $OUTPUT
	rm $HOST.tmp
done

mv $OUTPUT /var/www/html/mrtg/mrtg.cfg
