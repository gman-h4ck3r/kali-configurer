#!/bin/bash
#Author: Guillermo Lafuente
#Designed for: Kali Linux 2021.1
#Note: Run after clean install or after applying the latest updates to Kali

##### Setting variables for colour outputs
RED="\033[01;31m"      	# Errors
GREEN="\033[01;32m"    	# OK
YELLOW="\033[01;33m"   	# Warnings/Information
BOLD="\033[01;01m"     	# Highlight
RESET="\033[00m" 	# Normal

##### Getting the username running the script, we need this because it runs with sudo and otherwise it would take root as the user
username=$(logname)
homedir=$(echo "/home/$username")

##########################
# 	Help menu	 #
##########################

usage()
{
echo "Usage: "$0" [-a] [-m] [-h] -- Kali configurer will configure Kali with additional loggin capabilities, install additional tools and browser pluggins and set the environment to be ready to go

where:
    -h, --help          show this help text
    -d, --default       install additional utilities excluding mobile and cross-compile tools
    -a, --all           install all additional tools
    -m, --mobile        install mobile pentetration test tools
    -c, --cross         install tools to cross-compile for 32-bit version exploits

Example usage: sudo "$0" -d

Note: you need to run the script with root privileges"
}


##########################
#Command Line arguments  #
##########################

if [[ $# -eq 0 ]] ; then
    usage
    exit 0
fi

while [ -n "$1" ]; do
    case "$1" in
        -m | --mobile )         mobile=1
                                shift 1;;
        -c | --cross )          cross=1
                                shift 1;;
        -a | --all )            mobile=1
                                cross=1
                                break;;
        -d | --default )        break;;
        -h | --help )           usage
                                exit 0;;
        * )                     usage
                                exit 1;;
    esac
done


##########################
#	   MAIN  	 #
##########################

##### Check if we are running as root
if [[ "${EUID}" -ne 0 ]]; then
  echo -e ${RED}'[-]'${RESET}" This script must be run as ${BOLD}root${RESET}!" 1>&2
  echo -e ${RED}'[-]'${RESET}" Quitting..." 1>&2
  exit 1
else
  echo -e ${GREEN}'[+]'${RESET} ${BOLD}"Starting Kali 2021.1 post-install script${RESET}"
  sleep 2s
fi

echo -e ${YELLOW}'[*]'${RESET}" Updating Kali..." 1>&2

######################################DEBCONF CONFIGURATION FOR INSTALLED PACKAGES#########################################
#Pre-configuring debconf to avoid prompts during installation (Kudos to Joseph Hesse):
#Wireshark configuration
echo "wireshark-common wireshark-common/install-setuid  boolean false" | debconf-set-selections

#kismet configuration 
echo "kismet kismet/install-setuid boolean false" |  debconf-set-selections
echo "kismet kismet/install-users string" | debconf-set-selections

#ssh configuration
echo "sslh sslh/inetd_or_standalone select standalone" |  debconf-set-selections
echo "openssh-server openssh-server/permit-root-login boolean true" | debconf-set-selections

#configure mysql
echo "mariadb-server-10.5 mysql-server/root_password_again password" |  debconf-set-selections
echo "mariadb-server-10.5 mysql-server/root_password password" |  debconf-set-selections
echo "mariadb-server-10.5 mariadb-server-10.5/postrm_remove_databases boolean false" |  debconf-set-selections
echo "mariadb-server-10.5 mariadb-server-10.5/start_on_boot boolean true" |  debconf-set-selections
echo "mariadb-server-10.5 mariadb-server-10.5/nis_warning note" |  debconf-set-selections
echo "mariadb-server-10.5 mariadb-server-10.5/really_downgrade boolean false" |  debconf-set-selections

#postgres configuration
echo "postgresql-common postgresql-common/obsolete-major boolean true" | debconf-set-selections

#do not report list changes
echo "apt-listchanges apt-listchanges/confirm boolean false" | debconf-set-selections

###################################END OF DEBCONF CONFIGURATION FOR INSTALLED PACKAGES#####################################

##### Apply all the latest updates (-o Dpkg::Options::="--force-confnew" will avoid prompts when config files are changed)
apt-get update && apt-get -y -o Dpkg::Options::="--force-confnew" dist-upgrade && apt-get autoremove -y
echo -e ${GREEN}'[+]'${RESET}" Kali is now up to date." 1>&2

#Check if postgresql-9.5 was upgraded to 9.6 and configure accordingly
#2017.2 fixed this as it already includes 9.6 directly, leaving code commented in case is needed again in future (e.g. upgrade from 9.6 to 9.7)
#if [ "$(apt -qq list postgresql-9.5 2> /dev/null )" ] && [ "$(apt -qq list postgresql-9.6 2> /dev/null )" ] ; then
#	echo -e ${YELLOW}'[*]'${RESET}" Postgresql-9.5 was upgraded to 9.6, setting up upgraded version and removing the old one..." 1>&2
#	pg_dropcluster 9.6 main --stop
#	pg_upgradecluster 9.5 main
#	pg_dropcluster 9.5 main
#	apt-get -y purge postgresql-9.5 postgresql-client-9.5
#       echo -e ${GREEN}'[+]'${RESET}" Postgresql-9.6 ready!" 1>&2
#fi

echo -e ${YELLOW}'[*]'${RESET}" Configuring Metasploit..." 1>&2

#Configure MSF:
mkdir $homedir/.msf4 > /dev/null
echo '[framework/core]' > $homedir/.msf4/config
echo 'PROMPT=%red%L' >> $homedir/.msf4/config
echo 'ConsoleLogging=yes' >> $homedir/.msf4/config
echo 'SessionLogging=yes' >> $homedir/.msf4/config
echo '[framework/ui/console]' >> $homedir/.msf4/config

#msf database
systemctl enable postgresql
systemctl start postgresql
msfdb init

echo -e ${YELLOW}'[*]'${RESET}" Installing extra utilities..." 1>&2
#Utils and useful dependencies that may not be installed by default:
apt-get -y install git git-core autoconf automake autopoint libtool pkg-config build-essential dia steghide &> /dev/null
#Ensuring all tools to decompress files are installed:
apt-get -y install unrar unace rar unrar p7zip zip unzip p7zip-full p7zip-rar file-roller &> /dev/null
echo -e ${GREEN}'[+]'${RESET}" 50% done" 1>&2
#Windows cross compiler that we can use to compile in Linux Windows exploits
apt-get -y install mingw-w64
#HexEditor
apt-get -y install bless &> /dev/null
#Code comparison - useful for code review
apt-get -y install meld &> /dev/null
echo -e ${GREEN}'[+]'${RESET}" Done!" 1>&2

########## Cross-Compile Tools ##########

if [ "$cross" = "1" ]; then
	echo -e ${YELLOW}'[*]'${RESET}" Installing tools to allow cross-compilation for 32-bit targets..." 1>&2
	#libc6-dev-i386 allows you to crosscompile for 32-bit targets
	apt-get -y install libc6-dev-i386
	echo -e ${GREEN}'[+]'${RESET}" Done!" 1>&2
fi

echo -e ${YELLOW}'[*]'${RESET}" Installing tools for network penetration test..."
#Extra tools needed for network pentest
apt-get -y install responder crackmapexec freerdp2-x11 rwho rsh-client cifs-utils eyewitness &> /dev/null
#tool to monitor network and ensure we do not cause issues in client network:
apt-get -y install mtr &> /dev/null
#tool to interact with the IPMI protocol:
apt-get -y install ipmitool freeipmi &> /dev/null
echo -e ${GREEN}'[+]'${RESET}" Done!" 1>&2

echo -e ${YELLOW}'[*]'${RESET}" Installing tools for Wireless testing"
#WPA2 enterprise testing tools
apt-get -y install freeradius freeradius-wpe hostapd hostapd-wpe &> /dev/null
echo -e ${GREEN}'[+]'${RESET}" Done!" 1>&2

########## Mobile Penetration Testing Tools ##########

if [ "$cross" = "1" ]; then
	echo -e ${YELLOW}'[*]'${RESET}" Installing mobile penetration testing tools..."
	#useful tools to work with iOS:
	apt-get -y install libimobiledevice-utils libimobiledevice-doc libplist-utils libplist-doc &> /dev/null
	#Andoid:
	apt-get -y install android-sdk
	apt-get -y install lib32z1 lib32ncurses5 lib32stdc++6 lib32z1
	echo y | android update sdk --no-ui -t 1,2,3
	echo -e ${GREEN}'[+]'${RESET}" Machine ready for mobile pwnage!"
fi

echo -e ${YELLOW}'[*]'${RESET}" Installing Web Application tools"
#attack toolkit for JBoss, ColdFusion, WebLogic, Tomcat, etc.
apt-get -y install clusterd &> /dev/null
echo -e ${GREEN}'[+]'${RESET}" Done!"

echo -e ${YELLOW}'[*]'${RESET}" Installing and configuring database tools..."
#tool to access Firebird databases:
apt-get -y install flamerobin &> /dev/null

#necessary packages and dependencies for oracle DB metasploit modules:
apt-get -y install libgmp-dev
mkdir /opt/oracle
unzip instantclient-basic-linux.x64-12.1.0.2.0.zip -d /opt/oracle &> /dev/null
unzip instantclient-sdk-linux.x64-12.1.0.2.0.zip -d /opt/oracle &> /dev/null
unzip instantclient-sqlplus-linux.x64-12.1.0.2.0.zip -d /opt/oracle &> /dev/null
ln /opt/oracle/instantclient_12_1/libclntsh.so.12.1 /opt/oracle/instantclient_12_1/libclntsh.so
echo export PATH=$PATH:/opt/oracle/instantclient_12_1 >> ~/.bashrc
echo export SQLPATH=/opt/oracle/instantclient_12_1 >> ~/.bashrc
echo export TNS_ADMIN=/opt/oracle/instantclient_12_1 >> ~/.bashrc
echo export LD_LIBRARY_PATH=/opt/oracle/instantclient_12_1 >> ~/.bashrc
echo export ORACLE_HOME=/opt/oracle/instantclient_12_1 >> ~/.bashrc
#source ~/.bashrc -> wanted to use this to reload bashrc but did not work, so exporting the variables for current bash session:
export PATH=$PATH:/opt/oracle/instantclient_12_1
export SQLPATH=/opt/oracle/instantclient_12_1
export TNS_ADMIN=/opt/oracle/instantclient_12_1
export LD_LIBRARY_PATH=/opt/oracle/instantclient_12_1
export ORACLE_HOME=/opt/oracle/instantclient_12_1
wget https://github.com/kubo/ruby-oci8/archive/ruby-oci8-2.1.8.zip
unzip ruby-oci8-2.1.8.zip &> /dev/null
cd ruby-oci8-ruby-oci8-2.1.8/
make
make install
cd ..
rm -r ruby-oci8-ruby-oci8-2.1.8/
rm ruby-oci8-2.1.8.zip
echo -e ${GREEN}'[+]'${RESET}" Done installing DB tools!"

echo -e ${YELLOW}'[*]'${RESET}" Configuring Firefox..."
#Start and kill firefox so all initial configuration files are created
export DISPLAY=:0.0
sudo -u $username timeout 15 firefox &> /dev/null
sudo -u $username timeout 5 killall -9 -q -w firefox-esr &> /dev/null

#####Disable security features that would disrupt pentesting
#Disable Google SafeBrowsing
grep -q -m1 'browser.safebrowsing.malware.enabled' $homedir/.mozilla/firefox/*.default*/'prefs.js' ;
if [ $? -eq 0 ];
	then sed -i 's/^.browser.safebrowsing.malware.enabled*/user_pref("browser.safebrowsing.malware.enabled", false)/' $homedir/.mozilla/firefox/*.default*/'prefs.js';
	else echo 'user_pref("browser.safebrowsing.malware.enabled", false);' >> $homedir/.mozilla/firefox/*.default*/'prefs.js';
fi
grep -q -m1 'browser.safebrowsing.phishing.enabled' $homedir/.mozilla/firefox/*.default*/'prefs.js' ;
if [ $? -eq 0 ];
        then sed -i 's/^browser.safebrowsing.phishing.enabled*/user_pref("browser.safebrowsing.phishing.enabled", false)/' $homedir/.mozilla/firefox/*.default*/'prefs.js';
	else echo 'user_pref("browser.safebrowsing.phishing.enabled", false);' >> $homedir/.mozilla/firefox/*.default*/'prefs.js';
fi
grep -q -m1 'browser.safebrowsing.downloads.enabled' $homedir/.mozilla/firefox/*.default*/'prefs.js' ;
if [ $? -eq 0 ];
        then sed -i 's/^browser.safebrowsing.downloads.enabled*/user_pref("browser.safebrowsing.downloads.enabled", false)/' $homedir/.mozilla/firefox/*.default*/'prefs.js';
	else echo 'user_pref("browser.safebrowsing.downloads.enabled", false);' >> $homedir/.mozilla/firefox/*.default*/'prefs.js';
fi
#Enable do not track
grep -q -m1 'privacy.donottrackheader.enabled' $homedir/.mozilla/firefox/*.default*/'prefs.js' ;
if [ $? -eq 0 ];
        then sed -i 's/^privacy.donottrackheader.enabled*/user_pref("privacy.donottrackheader.enabled", true)/' $homedir/.mozilla/firefox/*.default*/'prefs.js';
	else echo 'user_pref("privacy.donottrackheader.enabled", true);' >> $homedir/.mozilla/firefox/*.default*/'prefs.js';
fi
#Disable geolocation
grep -q -m1 'geo.enabled' $homedir/.mozilla/firefox/*.default*/'prefs.js' ;
if [ $? -eq 0 ];
        then sed -i 's/^geo.enabled*/user_pref("geo.enabled", false)/' $homedir/.mozilla/firefox/*.default*/'prefs.js';
	else echo 'user_pref("geo.enabled", false);' >> $homedir/.mozilla/firefox/*.default*/'prefs.js';
fi

#### Adding Firefox addons:
ffpath="$(find ~/.mozilla/firefox/*.default*/ -maxdepth 0 -mindepth 0 -type d -name '*.default*' -print -quit)"
mkdir ${ffpath}extensions
ffpath="$(find ~/.mozilla/firefox/*.default*/ -maxdepth 0 -mindepth 0 -type d -name '*.default*' -print -quit)"extensions
#firebug
curl --progress -k -L -f "https://addons.mozilla.org/firefox/downloads/latest/1843/addon-1843-latest.xpi?src=dp-btn-primary" \
-o "${ffpath}/firebug@software.joehewitt.com.xpi"
#foxyproxy
curl --progress -k -L -f "https://addons.mozilla.org/firefox/downloads/latest/15023/addon-15023-latest.xpi?src=dp-btn-primary" \
-o "${ffpath}/foxyproxy-basic@eric.h.jung.xpi"
#SOA client
curl --progress -k -L -f "https://addons.mozilla.org/firefox/downloads/latest/soa-client/addon-57669-latest.xpi?src=dp-btn-primary" -o "${ffpath}/soaclient@santoso.xpi"

echo -e ${GREEN}'[+]'${RESET}" Firefox is ready!"

#Secure and configure SSH:
echo -e ${YELLOW}'[*]'${RESET}" Configuring SSH..."
#Configure the service to start on power on:
update-rc.d -f ssh remove
update-rc.d -f ssh defaults
#Change default keys and create new ones:
mkdir /etc/ssh/original_kali_keys
mv /etc/ssh/ssh_host_* /etc/ssh/original_kali_keys/
dpkg-reconfigure openssh-server
#Note that you may need to change /etc/ssh/sshd_config to permit password root login:
#PermitRootLogin yes
#restart SSH:
service ssh restart
update-rc.d -f ssh enable 2 3 4 5
echo -e ${GREEN}'[+]'${RESET}" Done!"

#make a folder and place inside useful tools not available from apt:
mkdir $homedir/Desktop/tools
wget -P $homedir/Desktop/tools https://github.com/java-decompiler/jd-gui/releases/download/v1.4.0/jd-gui-1.4.0.jar
wget -P $homedir/Desktop/tools https://pypi.python.org/packages/49/6f/183063f01aae1e025cf0130772b55848750a2f3a89bfa11b385b35d7329d/requests-2.10.0.tar.gz#md5=a36f7a64600f1bfec4d55ae021d232ae
wget -P $homedir/Desktop/tools https://downloads.sourceforge.net/project/laudanum/laudanum-1.0/laudanum-1.0.tgz
git clone https://github.com/pentestmonkey/exploit-suggester $homedir/Desktop/tools/exploit_suggester_solaris
git clone https://github.com/PenturaLabs/Linux_Exploit_Suggester $homedir/Desktop/tools/exploit_suggester_linux
git clone https://github.com/IOActive/jdwp-shellifier $homedir/Desktop/tools/jdwp-shellifier
#geckodriver for EyeWitness
wget -P $homedir/Desktop/tools https://github.com/mozilla/geckodriver/releases/download/v0.15.0/geckodriver-v0.15.0-linux64.tar.gz
git clone https://github.com/sixdub/DomainTrustExplorer $homedir/Desktop/tools/domainTrustExplorer
git clone https://github.com/libyal/libesedb $homedir/Desktop/tools/libesedb
git clone https://github.com/csababarta/ntdsxtract $homedir/Desktop/tools/ntdsxtract
git clone https://github.com/huntergregal/mimipenguin $homedir/Desktop/tools/mimipenguin

#Exploit suggester dependencies:
#setting variables so that yes is automatically answered when asking on install
export PERL_MM_USE_DEFAULT=1
export PERL_EXTUTILS_AUTOINSTALL="--defaultdeps"

cpan install XML::Simple

#Install Nessus:
#dpkg -i Nessus-6.10.5-debian6_amd64.deb

echo -e ${YELLOW}'[*]'${RESET}" Configuring FTP..."
apt-get -y install pure-ftpd &> /dev/null
#Create a new group to use with the FTP server:
groupadd ftpgroup
#Add a new user called ftpuser in the group ftpgroup, without home directory and with no permission for shell:
useradd -g ftpgroup -d /dev/null -s /etc ftpuser
#Create a virtual FTP user:
(echo ftppass; echo ftppass) | pure-pw useradd username -u ftpuser -g ftpgroup -d /home/ftphome/
#Update the FTP database with the new info:
pure-pw mkdb
#Create a hard link so that PureDB authentication is used when accessing the FTP server:
cd /etc/pure-ftpd/auth/
ln -s ../conf/PureDB 60pdb
#Create a home directory for the FTP server and give appropriate permissions:
mkdir /home/ftphome
chown -R ftpuser:ftpgroup /home/ftphome/
#Restart the service:
/etc/init.d/pure-ftpd restart
#We don't want the FTP enable by default:
update-rc.d -f pure-ftpd remove
echo -e ${GREEN}'[+]'${RESET}" FTP server Ready!"

echo -e ${YELLOW}'[*]'${RESET}" Configuring TFTP..."
apt-get -y install tftp atftpd &> /dev/null
echo -e "USE_INETD=false" > /etc/default/atftpd
echo -e 'OPTIONS="--daemon --port 69 --tftpd-timeout 300 --retry-timeout 5 --mcast-port 1758 --mcast-addr 239.239.239.0-255 --mcast-ttl 1 --maxthread 100 --verbose=5 /tftpboot"' >> /etc/default/atftpd
mkdir /tftpboot
chmod -R 777 /tftpboot
chown -R nobody:nogroup /tftpboot/
systemctl disable atftpd
echo -e ${GREEN}'[+]'${RESET}" TFTP server Ready!"

echo -e ${YELLOW}'[*]'${RESET}" Configuring XFCE..."
#Configuring timestampt for command history
echo 'export HISTTIMEFORMAT="%d/%m/%y %T "' >> ~/.bashrc
#Incresing size of history kept
echo 'export HISTSIZE=10000' >> ~/.bashrc
echo 'export HISTFILESIZE=10000' >> ~/.bashrc

#Delete useless default folders:
rm -r ~/Pictures/
rm -r ~/Music/
rm -r ~/Public/
rm -r ~/Templates/
rm -r ~/Videos/

#Configuring XFCE (Power Options)
cat <<EOF > ~/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-power-manager.xml \
  || echo -e ' '${RED}'[!] Issue with writing file'${RESET} 1>&2
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-power-manager" version="1.0">
  <property name="xfce4-power-manager" type="empty">
    <property name="power-button-action" type="empty"/>
    <property name="dpms-enabled" type="bool" value="true"/>
    <property name="blank-on-ac" type="int" value="0"/>
    <property name="dpms-on-ac-sleep" type="uint" value="0"/>
    <property name="dpms-on-ac-off" type="uint" value="0"/>
  </property>
</channel>
EOF

#TODO: Automatically add launchers for terminal, firefox, Burp
echo -e ${GREEN}'[+]'${RESET}" Desktop environment configured!"

echo -e ""
echo -e "To finish the set up, configure the following manually"
echo -e ${YELLOW}'[*]'${RESET}" Add Burp Suite Professional"
echo -e ${YELLOW}'[*]'${RESET}" Add Burp's certificate to trusted certs"
echo -e ${YELLOW}'[*]'${RESET}" Add Nessus professional licence and update plugins"
echo -e ${YELLOW}'[*]'${RESET}" Credentials for FTP are: ftpuser ftppass"
echo -e ${YELLOW}'[*]'${RESET}" This info will be stored as a reminder at $homedir/Desktop/todo.txt"

echo -e "To finish the set up, configure the following manually" > $homedir/Desktop/todo.txt
echo -e ${YELLOW}'[*]'${RESET}" Add Burp Suite Professional" >> $homedir/Desktop/todo.txt
echo -e ${YELLOW}'[*]'${RESET}" Add Burp's certificate to trusted certs" >> $homedir/Desktop/todo.txt
echo -e ${YELLOW}'[*]'${RESET}" Add Nessus professional licence and update plugins" >> $homedir/Desktop/todo.txt
echo -e ${YELLOW}'[*]'${RESET}" Credentials for FTP are: ftpuser ftppass" >> $homedir/Desktop/todo.txt

echo -e ${GREEN}'[+]'${RESET}" DONE! Enjoy! :)"

echo -e ${GREEN}'[+]'${RESET}" The machine will reboot"

updatedb
reboot
