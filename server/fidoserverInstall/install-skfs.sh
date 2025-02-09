#!/bin/bash
###################################################################################
# /**
# * Copyright StrongAuth, Inc. All Rights Reserved.
# *
# * Use of this source code is governed by the GNU Lesser General Public License v2.1
# * The license can be found at https://github.com/StrongKey/fido2/blob/master/LICENSE
# */
###################################################################################
# Uncomment to show detailed installation process
#SHOWALL=1

##########################################
##########################################
# Fido Server Info
FIDOSERVER_VERSION=4.4.1

# Server Passwords
LINUX_PASSWORD=ShaZam123
MARIA_ROOT_PASSWORD=BigKahuna
MARIA_SKFSDBUSER_PASSWORD=AbracaDabra

XMXSIZE=512m
BUFFERPOOLSIZE=512m

# JWT
RPID=strongkey.com
JWT_DN='CN=StrongKey KeyAppliance,O=StrongKey'
JWT_DURATION=30
JWT_KEYGEN_DN='/C=US/ST=California/L=Cupertino/O=StrongAuth/OU=Engineering'
JWT_CERTS_PER_SERVER=3
JWT_KEYSTORE_PASS=Abcd1234!
JWT_KEY_VALIDITY=365

##########################################
##########################################

# Flags to indicate if a module should be installed
INSTALL_GLASSFISH=Y
INSTALL_OPENDJ=Y
INSTALL_MARIA=Y
INSTALL_FIDO=Y

# Start Required Distributables
GLASSFISH=payara-5.2020.7.zip
JEMALLOC=jemalloc-3.6.0-1.el7.x86_64.rpm
MARIA=mariadb-10.5.8-linux-x86_64.tar.gz
MARIACONJAR=mariadb-java-client-2.2.6.jar
OPENDJ=OpenDJ-3.0.0.zip
# End Required Distributables

SERVICE_LDAP_BIND_PASS=Abcd1234!
SERVICE_LDAP_BASEDN='dc=strongauth,dc=com'
SAKA_DID=1
SERVICE_LDAP_SVCUSER_PASS=Abcd1234!
SKCE_LDIF=skce.ldif

# Other vars
STRONGKEY_HOME=/usr/local/strongkey
SKFS_HOME=$STRONGKEY_HOME/skfs
GLASSFISH_HOME=$STRONGKEY_HOME/payara5/glassfish
GLASSFISH_CONFIG=$GLASSFISH_HOME/domains/domain1/config
MARIAVER=mariadb-10.5.8-linux-x86_64
MARIATGT=mariadb-10.5.8
MARIA_HOME=$STRONGKEY_HOME/$MARIATGT
OPENDJVER=opendj
OPENDJTGT=OpenDJ-3.0.0
OPENDJ_HOME=$STRONGKEY_HOME/$OPENDJTGT
SKFS_SOFTWARE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SKCE_BASE_LDIF=skce-base.ldif
ALLOW_USERNAME_CHANGE=false

function check_exists {
for ARG in "$@"
do
    if [ ! -f $ARG ]; then
        >&2 echo -e "\E[31m$ARG Not Found. Check to ensure the file exists in the proper location and try again.\E[0m"
        exit 1
    fi
done
}

function get_ip {
        # Try using getent if it is available, best option
        if ! getent hosts $1 2>/dev/null | awk '{print $1; succ=1} END{exit !succ}'; then

                # If we are here, likely don't have getent. Try reading /etc/hosts.
                if ! awk "/^[^#].*$1/ "'{ print $1; succ=1} END{exit !succ}' /etc/hosts; then

                        # Wasn't in /etc/hosts, try DNS
                        if ! dig +short +time=2 +retry=1 +tries=1 $1 | grep '.' 2>/dev/null; then

                                # Can't resolve IP
                                >&2 echo -e "\E[31mFQDN $1 not resolvable. Modify DNS or add a hosts entry and try again.\E[0m"
                                exit 1
                        fi
                fi
        fi
}

# install required packages
YUM_CMD=$(which yum  2>/dev/null)
APT_GET_CMD=$(which apt-get 2>/dev/null)

echo -n "Installing required linux packages (openjdk, unzip, libaio, ncurses-compat-libs[only applicable for Amazon Linux], rng-tools, curl) ... "
echo -n "The installer will skip packages that do not apply or are already installed. "
if [[ ! -z $YUM_CMD ]]; then
    yum -y install unzip libaio java-1.8.0-openjdk ncurses-compat-libs rng-tools curl >/dev/null 2>&1
    yum downgrade java-1.8.0-openjdk-1.8.0.282.b08-1.el7_9 java-1.8.0-openjdk-headless-1.8.0.282.b08-1.el7_9 java-1.8.0-openjdk-devel-1.8.0.282.b08-1.el7_9 -y >/dev/null 2>&1
    systemctl restart rngd
elif [[ ! -z $APT_GET_CMD ]]; then
    apt-get update >/dev/null 2>&1
    apt install unzip libncurses5 libaio1 dbus openjdk-8-jdk-headless daemon rng-tools curl -y >/dev/null 2>&1
    # modify rng tools to use dev urandom as the vm may not have a harware random number generator
    if ! grep -q "^HRNGDEVICE=/dev/urandom" /etc/default/rng-tools ; then
            echo "HRNGDEVICE=/dev/urandom" | sudo tee -a /etc/default/rng-tools
    fi
    systemctl restart rng-tools
else
   echo "error can't install packages"
   exit 1;
fi
echo "Successful"

JAVA_CMD=$(java -version 2>&1 >/dev/null | egrep "\S+\s+version")

if [[ ! -z $JAVA_CMD ]]; then
        :
else
        echo "java binary does not exist or cannot be executed"
        exit 1
fi

# download required software
if [ ! -f $SKFS_SOFTWARE/$GLASSFISH ]; then
        echo -n "Downloading Payara ... "
	wget https://repo1.maven.org/maven2/fish/payara/distributions/payara/5.2020.7/payara-5.2020.7.zip -q
        echo "Successful"
fi

if [ ! -f $SKFS_SOFTWARE/$MARIA ]; then
        echo -n "Downloading Mariadb Server ... "
        wget https://downloads.mariadb.com/MariaDB/mariadb-10.5.8/bintar-linux-x86_64/mariadb-10.5.8-linux-x86_64.tar.gz -q
        echo "Successful"
fi

if [ ! -f $SKFS_SOFTWARE/$MARIACONJAR ]; then
        echo -n "Downloading Mariadb JAVA Connector ... "
        wget https://downloads.mariadb.com/Connectors/java/connector-java-2.2.6/mariadb-java-client-2.2.6.jar -q
        echo "Successful"
fi

if [ ! -f $SKFS_SOFTWARE/$JEMALLOC ]; then
        echo -n "Downloading Jemalloc ... "
        wget https://download-ib01.fedoraproject.org/pub/epel/7/x86_64/Packages/j/jemalloc-3.6.0-1.el7.x86_64.rpm -q
        echo "Successful"
fi


if [ ! -f $SKFS_SOFTWARE/$OPENDJ ]; then
        echo -n "Downloading OpenDJ ... "
        wget https://github.com/OpenRock/OpenDJ/releases/download/3.0.0/OpenDJ-3.0.0.zip -q
        echo "Successful"
fi

# Make sure we can resolve our own hostname
get_ip "$(hostname)" > /dev/null

# Check that the script is run as root
if [ $UID -ne 0 ]; then
        >&2 echo -e "\E[31m$0 must be run as root\E[0m"
        exit 1
fi

# Check that strongkey doesn't already exist
if $(id strongkey &> /dev/null); then
        >&2 echo -e "\E[31m'strongkey' user already exists. Run cleanup.sh and try again.\E[0m"
        exit 1
fi

# Check that all files are present
if [ $INSTALL_GLASSFISH = 'Y' ]; then
        check_exists $SKFS_SOFTWARE/$GLASSFISH
fi

if [ $INSTALL_MARIA = 'Y' ]; then
        check_exists $SKFS_SOFTWARE/$MARIA $SKFS_SOFTWARE/$JEMALLOC $SKFS_SOFTWARE/$MARIACONJAR
fi

if [ $INSTALL_FIDO = 'Y' ]; then
        check_exists $SKFS_SOFTWARE/signingkeystore.bcfks $SKFS_SOFTWARE/signingtruststore.bcfks
fi

# Make backup directory if not there
if [ -d /etc/org ]; then
        :
else
        mkdir /etc/org
        if [ -f /etc/bashrc ]; then
                cp /etc/bashrc /etc/org
        else
                cp /etc/bash.bashrc /etc/org
        fi
        cp /etc/sudoers /etc/org
fi

# Create the strongkey group and user, and add it to /etc/sudoers
groupadd strongkey
useradd -g strongkey -c"StrongKey" -d $STRONGKEY_HOME -m strongkey
echo strongkey:$LINUX_PASSWORD | /usr/sbin/chpasswd
cat >> /etc/sudoers <<-EOFSUDOERS

## SKFS permissions
Cmnd_Alias SKFS_COMMANDS = /usr/sbin/service glassfishd start, /usr/sbin/service glassfishd stop, /usr/sbin/service glassfishd restart, /usr/sbin/service mysqld start, /usr/sbin/service mysqld stop, /usr/sbin/service mysqld restart
strongkey ALL=SKFS_COMMANDS
EOFSUDOERS

##### Create skfsrc #####
cat > /etc/skfsrc << EOFSKFSRC
    export GLASSFISH_HOME=$GLASSFISH_HOME
        export MYSQL_HOME=$MARIA_HOME
        export OPENDJ_HOME=$OPENDJ_HOME
   export STRONGKEY_HOME=$STRONGKEY_HOME
              export PATH=\$OPENDJ_HOME/bin:\$GLASSFISH_HOME/bin:\$MYSQL_HOME/bin:\$STRONGKEY_HOME/bin:/usr/lib64/qt-3.3/bin:/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin:/root/bin:/root/bin

alias str='cd $STRONGKEY_HOME'
alias dist='cd $STRONGKEY_HOME/dist'
alias aslg='cd $GLASSFISH_HOME/domains/domain1/logs'
alias ascfg='cd $GLASSFISH_HOME/domains/domain1/config'
alias tsl='tail --follow=name $GLASSFISH_HOME/domains/domain1/logs/server.log'
alias mys='mysql -u skfsdbuser -p\`dbpass 2> /dev/null\` skfs'
alias java='java -Djavax.net.ssl.trustStore=\$STRONGKEY_HOME/certs/cacerts '
EOFSKFSRC

if [ -f /etc/bashrc ]; then
        echo ". /etc/skfsrc" >> /etc/bashrc
else
        echo ". /etc/skfsrc" >> /etc/bash.bashrc
fi

# Make needed directories
mkdir -p $STRONGKEY_HOME/certs $STRONGKEY_HOME/Desktop $STRONGKEY_HOME/dbdumps $STRONGKEY_HOME/lib $STRONGKEY_HOME/bin $STRONGKEY_HOME/appliance/etc $STRONGKEY_HOME/crypto/etc $SKFS_HOME/etc $SKFS_HOME/keystores

##### Install Fido #####
cp $SKFS_SOFTWARE/certimport.sh $STRONGKEY_HOME/bin
if [ $INSTALL_FIDO = 'Y' ]; then

        echo -n "Installing StrongKey FIDO2 Server (SKFS) ... "

        cp $STRONGKEY_HOME/bin/* $STRONGKEY_HOME/Desktop/

        chmod 700 $STRONGKEY_HOME/Desktop/*.sh

        SERVICE_LDAP_USERNAME=$(sed -r 's|^[cC][nN]=([^,]*),.*|\1|' <<< "$SERVICE_LDAP_SVCUSER_DN")
        SERVICE_LDAP_SUFFIX=$(sed -r 's|^[cC][nN]=[^,]*(,.*)|\1|' <<< "$SERVICE_LDAP_SVCUSER_DN")

        SERVICE_LDAP_PINGUSER=$(sed -r 's|^[cC][nN]=([^,]*),.*|\1|' <<< "$SERVICE_LDAP_PINGUSER_DN")
        SERVICE_LDAP_PINGUSER_SUFFIX=$(sed -r 's|^[cC][nN]=[^,]*(,.*)|\1|' <<< "$SERVICE_LDAP_PINGUSER_DN")

        if [ "${SERVICE_LDAP_SUFFIX}" != "${SERVICE_LDAP_PINGUSER_SUFFIX}" ]; then
                echo "Warning: SERVICE_LDAP_USER and SERVICE_LDAP_PINGUSER must be in the same OU. Pinguser may not authenticate as expected. Run update-ldap-config with corrected users."
        fi

        cp $SKFS_SOFTWARE/signingkeystore.bcfks $SKFS_SOFTWARE/signingtruststore.bcfks $SKFS_HOME/keystores
        cp -R $SKFS_SOFTWARE/keymanager $STRONGKEY_HOME/
        cp -R $SKFS_SOFTWARE/skfsclient $STRONGKEY_HOME/
        echo "Successful"

fi

##### MariaDB #####
if [ $INSTALL_MARIA = 'Y' ]; then
        echo -n "Installing MariaDB... "
        if [ $SHOWALL ]; then
                tar zxvf $SKFS_SOFTWARE/$MARIA -C $STRONGKEY_HOME
        else
                tar zxf $SKFS_SOFTWARE/$MARIA -C $STRONGKEY_HOME
        fi

        rpm -ivh $SKFS_SOFTWARE/$JEMALLOC &> /dev/null
        sed -i 's|^mysqld_ld_preload=$|mysqld_ld_preload=/usr/lib64/libjemalloc.so.1|' $STRONGKEY_HOME/$MARIAVER/bin/mysqld_safe
        cp $STRONGKEY_HOME/$MARIAVER/support-files/mysql.server /etc/init.d/mysqld
        chmod 755 /etc/init.d/mysqld
        /lib/systemd/systemd-sysv-install enable mysqld
        mkdir $STRONGKEY_HOME/$MARIAVER/backups $STRONGKEY_HOME/$MARIAVER/binlog $STRONGKEY_HOME/$MARIAVER/log $STRONGKEY_HOME/$MARIAVER/ibdata
        mv $STRONGKEY_HOME/$MARIAVER $STRONGKEY_HOME/$MARIATGT
        DBSIZE=10M
        SERVER_BINLOG=$STRONGKEY_HOME/$MARIATGT/binlog/skfs-binary-log

        cat > /etc/my.cnf <<-EOFMYCNF
	[client]
	socket                          = /usr/local/strongkey/$MARIATGT/log/mysqld.sock

	[mysqld]
	user                            = strongkey
	lower_case_table_names          = 1
	log-bin                         = $SERVER_BINLOG

	[server]
	basedir                         = /usr/local/strongkey/$MARIATGT
	datadir                         = /usr/local/strongkey/$MARIATGT/ibdata
	pid-file                        = /usr/local/strongkey/$MARIATGT/log/mysqld.pid
	socket                          = /usr/local/strongkey/$MARIATGT/log/mysqld.sock
	general_log                     = 0
	general_log_file                = /usr/local/strongkey/$MARIATGT/log/mysqld.log
	log-error                       = /usr/local/strongkey/$MARIATGT/log/mysqld-error.log
	innodb_data_home_dir            = /usr/local/strongkey/$MARIATGT/ibdata
	innodb_data_file_path           = ibdata01:$DBSIZE:autoextend
	innodb_flush_method             = O_DIRECT
	innodb_buffer_pool_size         = ${BUFFERPOOLSIZE}
	innodb_log_file_size            = 512M
	innodb_log_buffer_size          = 5M
	innodb_flush_log_at_trx_commit  = 1
	sync_binlog                     = 1
	lower_case_table_names          = 1
	max_connections                 = 1000
	thread_cache_size               = 1000
	expire_logs_days                = 10
	EOFMYCNF

        echo "Successful"
fi

##################
MYSQL_CMD=$($MARIA_HOME/bin/mysql --version 2>/dev/null)
if [[ ! -z $MYSQL_CMD ]]; then
      :
else
      echo "mysql binary does not exist or cannot be executed."
      exit 1
fi
##################

##### Payara #####
if [ $INSTALL_GLASSFISH = 'Y' ]; then
        echo -n "Installing Payara... "
        if [ $SHOWALL ]; then
                unzip $SKFS_SOFTWARE/$GLASSFISH -d $STRONGKEY_HOME
        else
                unzip $SKFS_SOFTWARE/$GLASSFISH -d $STRONGKEY_HOME > /dev/null
        fi

        if [ -d /root/.gfclient ]; then
                rm -rf /root/.gfclient
        fi

        if [ -d $STRONGKEY_HOME/.gfclient ]; then
                rm -rf $STRONGKEY_HOME/.gfclient
        fi

        cp $SKFS_SOFTWARE/glassfishd /etc/init.d
        chmod 755 /etc/init.d/glassfishd
        /lib/systemd/systemd-sysv-install enable glassfishd

        keytool -genkeypair -alias skfs -keystore $GLASSFISH_CONFIG/keystore.jks -storepass changeit -keypass changeit -keyalg RSA -keysize 2048 -sigalg SHA256withRSA -validity 3562 -dname "CN=$(hostname),OU=\"StrongKey FidoServer\"" &>/dev/null
        keytool -changealias -alias s1as -destalias s1as.original -keystore $GLASSFISH_CONFIG/keystore.jks -storepass changeit &>/dev/null
        keytool -changealias -alias skfs -destalias s1as -keystore $GLASSFISH_CONFIG/keystore.jks -storepass changeit &>/dev/null
        sed -ri 's|^(com.sun.enterprise.server.logging.GFFileHandler.rotationOnDateChange=).*|\1true|
                 s|^(com.sun.enterprise.server.logging.GFFileHandler.rotationLimitInBytes=).*|\1200000000|' $GLASSFISH_CONFIG/logging.properties
        keytool -exportcert -alias s1as -file $STRONGKEY_HOME/certs/$(hostname).der --keystore $GLASSFISH_CONFIG/keystore.jks -storepass changeit &>/dev/null
        keytool -importcert -noprompt -alias $(hostname) -file $STRONGKEY_HOME/certs/$(hostname).der --keystore $STRONGKEY_HOME/certs/cacerts -storepass changeit &>/dev/null
        keytool -importcert -noprompt -alias $(hostname) -file $STRONGKEY_HOME/certs/$(hostname).der --keystore $GLASSFISH_CONFIG/cacerts.jks -storepass changeit &>/dev/null

        echo "Successful"
        ##### MariaDB JDBC Driver #####
        echo -n "Installing JDBC Driver... "
        cp $SKFS_SOFTWARE/$MARIACONJAR $GLASSFISH_HOME/lib
        echo "Successful"
fi

if [ $INSTALL_OPENDJ = 'Y' ]; then
        echo -n "Installing OpenDJ... "
        if [ $SHOWALL ]; then
                unzip $SKFS_SOFTWARE/$OPENDJ -d $STRONGKEY_HOME
        else
                unzip $SKFS_SOFTWARE/$OPENDJ -d $STRONGKEY_HOME > /dev/null
        fi

        mv $STRONGKEY_HOME/$OPENDJVER $OPENDJ_HOME

        cp $SKFS_SOFTWARE/99-user.ldif $OPENDJ_HOME/template/config/schema

        export "OPENDJ_JAVA_HOME=$JAVA_HOME"
        if [ $SHOWALL ]; then
                $OPENDJ_HOME/setup --cli --acceptLicense --no-prompt \
                                   --ldifFile $SKFS_SOFTWARE/$SKCE_BASE_LDIF \
                                   --rootUserPassword $SERVICE_LDAP_BIND_PASS \
                                   --baseDN $SERVICE_LDAP_BASEDN \
                                   --hostname $(hostname) \
                                   --ldapPort 1389 \
                                   --doNotStart
        else
                $OPENDJ_HOME/setup --cli --acceptLicense --no-prompt \
                                   --ldifFile $SKFS_SOFTWARE/$SKCE_BASE_LDIF \
                                   --rootUserPassword $SERVICE_LDAP_BIND_PASS \
                                   --baseDN $SERVICE_LDAP_BASEDN \
                                   --hostname $(hostname) \
                                   --ldapPort 1389 \
                                   --doNotStart \
                                   --quiet
        fi


        sed -i '/^control-panel/s|$| -Dcom.sun.jndi.ldap.object.disableEndpointIdentification=true|' $OPENDJ_HOME/config/java.properties
        $OPENDJ_HOME/bin/dsjavaproperties >/dev/null

        cp $SKFS_SOFTWARE/opendjd /etc/init.d/
        chmod 755 /etc/init.d/opendjd
        /lib/systemd/systemd-sysv-install enable opendjd
        echo "Successful"
fi

##### Change ownership of files #####
chown -R strongkey:strongkey $STRONGKEY_HOME

##### Start OpenDJ #####
if [ $INSTALL_OPENDJ = 'Y' ]; then
        service opendjd restart
        sleep 10;
        $OPENDJ_HOME/bin/dsconfig set-global-configuration-prop \
                                  --hostname $(hostname) \
                                  --port 4444 \
                                  --bindDN "cn=Directory Manager" \
                                  --bindPassword "$SERVICE_LDAP_BIND_PASS" \
                                  --set check-schema:false \
                                  --trustAll \
                                  --no-prompt
fi

##### Adding default opendj users #####
SLDNAME=${SERVICE_LDAP_BASEDN%%,dc*}
sed -r "s|dc=strongauth,dc=com|$SERVICE_LDAP_BASEDN|
        s|dc: strongauth|dc: ${SLDNAME#dc=}|
        s|did: .*|did: ${SAKA_DID}|
        s|did=[0-9]+,|did=${SAKA_DID},|
        s|^ou: [0-9]+|ou: ${SAKA_DID}|
        s|(domain( id)*) [0-9]*|\1 ${SAKA_DID}|
        s|userPassword: .*|userPassword: $SERVICE_LDAP_SVCUSER_PASS|" $SKFS_SOFTWARE/$SKCE_LDIF > /tmp/skce.ldif

echo -n "Importing default users... "
$OPENDJ_HOME/bin/ldapmodify --filename /tmp/skce.ldif \
                             --hostName $(hostname) \
                             --port 1389 \
                             --bindDN 'cn=Directory Manager' \
                             --bindPassword "$SERVICE_LDAP_BIND_PASS" \
                             --trustAll \
                             --noPropertiesFile \
                             --defaultAdd >/dev/null

echo "Successful"

##### Start MariaDB and Payara #####
echo -n "Creating $DBSIZE SKFS Internal Database..."
cd $STRONGKEY_HOME/$MARIATGT
scripts/mysql_install_db --basedir=`pwd` --datadir=`pwd`/ibdata &>/dev/null
# Sleep till the database is created
bin/mysqld_safe &>/dev/null &
READY=`grep "ready for connections" $MARIA_HOME/log/mysqld-error.log | wc -l`
while [ $READY -ne 1 ]
do
        echo -n .
        sleep 3
        READY=`grep "ready for connections" $MARIA_HOME/log/mysqld-error.log | wc -l`
done
echo done

$MARIA_HOME/bin/mysql -u root mysql -e "set password for 'root'@localhost=password('$MARIA_ROOT_PASSWORD');
                                                    delete from mysql.db where host = '%';
                                                    delete from mysql.user where user = '';
						    flush privileges;"

if [ $INSTALL_FIDO = 'Y' ]; then
	$MARIA_HOME/bin/mysql -u root mysql -p$MARIA_ROOT_PASSWORD -e "create database skfs;
                                                    grant all on skfs.* to skfsdbuser@localhost identified by '$MARIA_SKFSDBUSER_PASSWORD';
                                                    flush privileges;"


	cd $SKFS_SOFTWARE/fidoserverSQL
	$STRONGKEY_HOME/$MARIATGT/bin/mysql --user=skfsdbuser --password=$MARIA_SKFSDBUSER_PASSWORD --database=skfs --quick < create.txt

	# Add server entries to SERVERS table
	$STRONGKEY_HOME/$MARIATGT/bin/mysql --user=skfsdbuser --password=$MARIA_SKFSDBUSER_PASSWORD --database=skfs -e "insert into SERVERS values (1, '$(hostname)', 'Active', 'Both', 'Active', null, null);"

	$STRONGKEY_HOME/$MARIATGT/bin/mysql --user=skfsdbuser --password=$MARIA_SKFSDBUSER_PASSWORD --database=skfs -e "insert into DOMAINS values (1,'SKFS','Active','Active','-----BEGIN CERTIFICATE-----\nMIIDizCCAnOgAwIBAgIENIYcAzANBgkqhkiG9w0BAQsFADBuMRcwFQYDVQQKEw5T\ndHJvbmdBdXRoIEluYzEjMCEGA1UECxMaU0tDRSBTaWduaW5nIENlcnRpZmljYXRl\nIDExEzARBgNVBAsTClNBS0EgRElEIDExGTAXBgNVBAMTEFNLQ0UgU2lnbmluZyBL\nZXkwHhcNMTkwMTMwMjI1NDAwWhcNMTkwNDMwMjI1NDAwWjBuMRcwFQYDVQQKEw5T\ndHJvbmdBdXRoIEluYzEjMCEGA1UECxMaU0tDRSBTaWduaW5nIENlcnRpZmljYXRl\nIDExEzARBgNVBAsTClNBS0EgRElEIDExGTAXBgNVBAMTEFNLQ0UgU2lnbmluZyBL\nZXkwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQCH/W7ERX0U3a+2VLBY\nyjpCRTCdRtiuiLv+C1j64gLAyseF5sMH+tLNcqU0WgdZ3uQxb2+nl2y8Cp0B8Cs9\nvQi9V9CIC7zvMvgveQ711JqX8RMsaGBrn+pWx61E4B1kLCYCPSI48Crm/xkMydGM\nTKXHpfb+t9uo/uat/ykRrel5f6F764oo0o1KJkY6DjFEMh9TKMbJIeF127S2pFxl\nNNBhawTDGDaA1ag9GoWHGCWZ/bbCMMiwcH6q71AqRg8qby1EsBKA7E4DD8f+5X6b\nU3zcY3kudKlYxP4rix42PHCY3B4ZnpWS3A6lZRBot7NklsLvlxvDbKIiTcyDvSA0\nunfpAgMBAAGjMTAvMA4GA1UdDwEB/wQEAwIHgDAdBgNVHQ4EFgQUlSKnwxvmv8Bh\nlkFSMeEtAM7AyakwDQYJKoZIhvcNAQELBQADggEBAG2nosn6cTsZTdwRGws61fhP\n+tvSZXpE5mYk93x9FTnApbbsHJk1grWbC2psYxzuY1nYTqE48ORPngr3cHcNX0qZ\npi9JQ/eh7AaCLQcb1pxl+fJAjnnHKCKpicyTvmupv6c97IE4wa2KoYCJ4BdnJPnY\nnmnePPqDvjnAhuCTaxSRz59m7aW4Tyt9VPsoBShrCSBYzK5cH3FNIGffqB7zI3Jh\nXo0WpVD/YBE/OsWRbthZ0OquJIfxcpdXS4srCFocQlqNMhlQ7ZVOs73WrRx+uGIr\nhUYvIJrqgAc7+F0I7v2nAQLmxMBYheZDhN9DA9LuJRV93A8ELIX338DKxBKBPPU=\n-----END CERTIFICATE-----',NULL,'-----BEGIN CERTIFICATE-----\nMIIDizCCAnOgAwIBAgIENIYcAzANBgkqhkiG9w0BAQsFADBuMRcwFQYDVQQKEw5T\ndHJvbmdBdXRoIEluYzEjMCEGA1UECxMaU0tDRSBTaWduaW5nIENlcnRpZmljYXRl\nIDExEzARBgNVBAsTClNBS0EgRElEIDExGTAXBgNVBAMTEFNLQ0UgU2lnbmluZyBL\nZXkwHhcNMTkwMTMwMjI1NDAwWhcNMTkwNDMwMjI1NDAwWjBuMRcwFQYDVQQKEw5T\ndHJvbmdBdXRoIEluYzEjMCEGA1UECxMaU0tDRSBTaWduaW5nIENlcnRpZmljYXRl\nIDExEzARBgNVBAsTClNBS0EgRElEIDExGTAXBgNVBAMTEFNLQ0UgU2lnbmluZyBL\nZXkwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQCH/W7ERX0U3a+2VLBY\nyjpCRTCdRtiuiLv+C1j64gLAyseF5sMH+tLNcqU0WgdZ3uQxb2+nl2y8Cp0B8Cs9\nvQi9V9CIC7zvMvgveQ711JqX8RMsaGBrn+pWx61E4B1kLCYCPSI48Crm/xkMydGM\nTKXHpfb+t9uo/uat/ykRrel5f6F764oo0o1KJkY6DjFEMh9TKMbJIeF127S2pFxl\nNNBhawTDGDaA1ag9GoWHGCWZ/bbCMMiwcH6q71AqRg8qby1EsBKA7E4DD8f+5X6b\nU3zcY3kudKlYxP4rix42PHCY3B4ZnpWS3A6lZRBot7NklsLvlxvDbKIiTcyDvSA0\nunfpAgMBAAGjMTAvMA4GA1UdDwEB/wQEAwIHgDAdBgNVHQ4EFgQUlSKnwxvmv8Bh\nlkFSMeEtAM7AyakwDQYJKoZIhvcNAQELBQADggEBAG2nosn6cTsZTdwRGws61fhP\n+tvSZXpE5mYk93x9FTnApbbsHJk1grWbC2psYxzuY1nYTqE48ORPngr3cHcNX0qZ\npi9JQ/eh7AaCLQcb1pxl+fJAjnnHKCKpicyTvmupv6c97IE4wa2KoYCJ4BdnJPnY\nnmnePPqDvjnAhuCTaxSRz59m7aW4Tyt9VPsoBShrCSBYzK5cH3FNIGffqB7zI3Jh\nXo0WpVD/YBE/OsWRbthZ0OquJIfxcpdXS4srCFocQlqNMhlQ7ZVOs73WrRx+uGIr\nhUYvIJrqgAc7+F0I7v2nAQLmxMBYheZDhN9DA9LuJRV93A8ELIX338DKxBKBPPU=\n-----END CERTIFICATE-----',NULL,'CN=SKFS Signing Key,OU=DID 1,OU=SKFS EC Signing Certificate 1,O=StrongKey','https://$(hostname):8181/app.json',NULL);"

        startDate=$(date +%s)
        fidoPolicy=$(echo "{\"FidoPolicy\":{\"name\":\"DefaultPolicy\",\"copyright\":\"\",\"version\":\"1.0\",\"startDate\":\"${startDate}\",\"endDate\":\"1760103870871\",\"system\":{\"requireCounter\":\"mandatory\",\"integritySignatures\":false,\"userVerification\":[\"required\",\"preferred\",\"discouraged\"],\"userPresenceTimeout\":0,\"allowedAaguids\":[\"all\"],\"jwtKeyValidity\":${JWT_KEY_VALIDITY},\"jwtRenewalWindow\":30},\"algorithms\":{\"curves\":[\"secp256r1\",\"secp384r1\",\"secp521r1\",\"curve25519\"],\"rsa\":[\"rsassa-pkcs1-v1_5-sha256\",\"rsassa-pkcs1-v1_5-sha384\",\"rsassa-pkcs1-v1_5-sha512\",\"rsassa-pss-sha256\",\"rsassa-pss-sha384\",\"rsassa-pss-sha512\"],\"signatures\":[\"ecdsa-p256-sha256\",\"ecdsa-p384-sha384\",\"ecdsa-p521-sha512\",\"eddsa\",\"ecdsa-p256k-sha256\"]},\"attestation\":{\"conveyance\":[\"none\",\"indirect\",\"direct\",\"enterprise\"],\"formats\":[\"fido-u2f\",\"packed\",\"tpm\",\"android-key\",\"android-safetynet\",\"apple\",\"none\"]},\"registration\":{\"displayName\":\"required\",\"attachment\":[\"platform\",\"cross-platform\"],\"residentKey\":[\"required\",\"preferred\",\"discouraged\"],\"excludeCredentials\":\"enabled\"},\"authentication\":{\"allowCredentials\":\"enabled\"},\"authorization\":{\"maxdataLength\":256,\"preserve\":true},\"rp\":{\"id\":\"${RPID}\",\"name\":\"FIDOServer\"},\"extensions\":{\"example.extension\":true},\"jwt\":{\"algorithms\":[\"ES256\",\"ES384\",\"ES521\"],\"duration\":${JWT_DURATION},\"required\":[\"rpid\",\"iat\",\"exp\",\"cip\",\"uname\",\"agent\"],\"signingCerts\":{\"DN\":\"${JWT_DN}\",\"certsPerServer\":${JWT_CERTS_PER_SERVER}}}}}" | /usr/bin/base64 -w 0)
        $STRONGKEY_HOME/$MARIATGT/bin/mysql --user=skfsdbuser --password=$MARIA_SKFSDBUSER_PASSWORD --database=skfs -e "insert into FIDO_POLICIES values (1,1,1,'${fidoPolicy}','Active','',NOW(),NULL,NULL);"

	touch $STRONGKEY_HOME/crypto/etc/crypto-configuration.properties
	echo "crypto.cfg.property.jwtsigning.certsperserver=$JWT_CERTS_PER_SERVER" >> $STRONGKEY_HOME/crypto/etc/crypto-configuration.properties
	chown -R strongkey:strongkey $STRONGKEY_HOME/crypto

	echo "appliance.cfg.property.serverid=1" > $STRONGKEY_HOME/appliance/etc/appliance-configuration.properties
	echo "appliance.cfg.property.enableddomains.ccspin=$CCS_DOMAINS" >> $STRONGKEY_HOME/appliance/etc/appliance-configuration.properties
	echo "appliance.cfg.property.replicate=false" >> $STRONGKEY_HOME/appliance/etc/appliance-configuration.properties
	chown -R strongkey:strongkey $STRONGKEY_HOME/appliance
	
	echo "skfs.cfg.property.allow.changeusername=$ALLOW_USERNAME_CHANGE" >> $STRONGKEY_HOME/skfs/etc/skfs-configuration.properties
	chown -R strongkey:strongkey $STRONGKEY_HOME/skfs
	
	mkdir -p $STRONGKEY_HOME/fido
	touch $STRONGKEY_HOME/fido/VersionFidoServer-$FIDOSERVER_VERSION
	chown -R strongkey:strongkey $STRONGKEY_HOME/fido
fi

service glassfishd start
sleep 10

##### Perform Payara Tasks #####
$GLASSFISH_HOME/bin/asadmin set server.network-config.network-listeners.network-listener.http-listener-1.enabled=false
$GLASSFISH_HOME/bin/asadmin set server.network-config.protocols.protocol.http-listener-2.http.request-timeout-seconds=7200
$GLASSFISH_HOME/bin/asadmin set server.network-config.protocols.protocol.http-listener-2.ssl.ssl3-tls-ciphers=+TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,+TLS_DHE_RSA_WITH_AES_256_GCM_SHA384,+TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA384,+TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA,+TLS_DHE_RSA_WITH_AES_256_CBC_SHA256,+TLS_DHE_RSA_WITH_AES_256_CBC_SHA
$GLASSFISH_HOME/bin/asadmin set server.network-config.protocols.protocol.http-listener-2.ssl.ssl2-enabled=false
$GLASSFISH_HOME/bin/asadmin set server.network-config.protocols.protocol.http-listener-2.ssl.ssl3-enabled=false
$GLASSFISH_HOME/bin/asadmin set server.network-config.protocols.protocol.http-listener-2.ssl.tls-enabled=false
$GLASSFISH_HOME/bin/asadmin set server.network-config.protocols.protocol.http-listener-2.ssl.tls11-enabled=false
$GLASSFISH_HOME/bin/asadmin set server.network-config.protocols.protocol.http-listener-2.http.trace-enabled=false
$GLASSFISH_HOME/bin/asadmin set server.network-config.protocols.protocol.http-listener-2.http.xpowered-by=false

if [ $INSTALL_FIDO = 'Y' ]; then
	$GLASSFISH_HOME/bin/asadmin create-jdbc-connection-pool \
        	--datasourceclassname org.mariadb.jdbc.MySQLDataSource \
        	--restype javax.sql.ConnectionPoolDataSource \
        	--isconnectvalidatereq=true \
        	--validationmethod meta-data \
        	--property ServerName=localhost:DatabaseName=skfs:port=3306:user=skfsdbuser:password=$MARIA_SKFSDBUSER_PASSWORD:DontTrackOpenResources=true \
        	SKFSPool
	$GLASSFISH_HOME/bin/asadmin create-jdbc-resource --connectionpoolid SKFSPool jdbc/strongkeylite
	$GLASSFISH_HOME/bin/asadmin set server.resources.jdbc-connection-pool.SKFSPool.max-pool-size=1000
	$GLASSFISH_HOME/bin/asadmin set server.thread-pools.thread-pool.http-thread-pool.max-thread-pool-size=1000
	$GLASSFISH_HOME/bin/asadmin set server.thread-pools.thread-pool.http-thread-pool.min-thread-pool-size=10
fi



$GLASSFISH_HOME/bin/asadmin delete-jvm-options $($GLASSFISH_HOME/bin/asadmin list-jvm-options | sed -n '/\(-XX:NewRatio\|-XX:MaxPermSize\|-XX:PermSize\|-client\|-Xmx\|-Xms\)/p' | sed 's|:|\\\\:|' | tr '\n' ':')
$GLASSFISH_HOME/bin/asadmin create-jvm-options -Djtss.tcs.ini.file=$STRONGKEY_HOME/lib/jtss_tcs.ini:-Djtss.tsp.ini.file=$STRONGKEY_HOME/lib/jtss_tsp.ini:-Xmx${XMXSIZE}:-Xms${XMXSIZE}:-Djdk.tls.ephemeralDHKeySize=2048:-Dproduct.name="":-XX\\:-DisableExplicitGC



if [ $INSTALL_FIDO = 'Y' ]; then

	# Create URL for first time setup
	install_date_millis=$(date +%s%3N)
	$MARIA_HOME/bin/mysql -u skfsdbuser -p${MARIA_SKFSDBUSER_PASSWORD} skfs -e "insert into configurations values(1, 'skfs.cfg.property.install.date.hash', '$(echo $(hostname)$install_date_millis | md5sum | cut -d ' ' -f 1)', 'Hash created during install to aid in first time setup');"

cat > $GLASSFISH_HOME/domains/domain1/docroot/app.json <<- EOFAPPJSON
{
  "trustedFacets" : [{
    "version": { "major": 1, "minor" : 0 },
    "ids": [
      "https://$(hostname)",
      "https://$(hostname):8181"
    ]
  }]
}
EOFAPPJSON

	# Add other servers to app.json
	for fqdn in $($MARIA_HOME/bin/mysql -u skfsdbuser -p${MARIA_SKFSDBUSER_PASSWORD} skfs -B --skip-column-names -e "select fqdn from servers;"); do
        	# Skip doing ourself again
        	if [ "$fqdn" == "$(hostname)" ]; then
                	continue
        	fi
        	sed -i "/^\[/a \"           https://$fqdn:8181\"," $GLASSFISH_HOME/domains/domain1/docroot/app.json
        	sed -i "/^\[/a \"           https://$fqdn\"," $GLASSFISH_HOME/domains/domain1/docroot/app.json
	done

	# Generate JWT keystores
	$SKFS_SOFTWARE/keygen-jwt.sh $JWT_KEYGEN_DN $($MARIA_HOME/bin/mysql -u skfsdbuser -p${MARIA_SKFSDBUSER_PASSWORD} skfs -B --skip-column-names -e "select count(fqdn) from servers;") $JWT_CERTS_PER_SERVER $SAKA_DID $JWT_KEYSTORE_PASS $JWT_KEY_VALIDITY
	chown strongkey:strongkey $SKFS_HOME/keystores/jwtsigningtruststore.bcfks $SKFS_HOME/keystores/jwtsigningkeystore.bcfks

	chown strongkey:strongkey $GLASSFISH_HOME/domains/domain1/docroot/app.json
	echo -n "Deploying StrongKey FidoServer ... "
	cp $SKFS_SOFTWARE/fidoserver.ear /tmp
	$GLASSFISH_HOME/bin/asadmin deploy /tmp/fidoserver.ear
	rm /tmp/fidoserver.ear

fi

# Future build
#echo "Please visit: https://$(hostname):8181/#/setup/$(echo $(hostname)$install_date_millis | md5sum | cut -d ' ' -f 1) for first time setup"

echo "Done!"
