# MRTG-Scripts
<br>
<br>
apt install librrds-perl<br>
apt install libcgi-session-perl<br>
<br>
In /etc/apache2/apache2.conf add the following:<br>
"<Directory /var/www/html/mrtg/*/>
        Options +ExecCGI
        AddHandler cgi-script .cgi .pl
</Directory>"
