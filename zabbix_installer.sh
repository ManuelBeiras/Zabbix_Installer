#!/bin/bash
#########################################################################################################
##Zabbix installation script 											                               ##
##Date: 14/10/2021                                                                                     ##
##Version 1.0:  Allows simple installation of Zabbix.							                       ##
##        If the installation of all components is done on the same machine                            ##
##        a fully operational version remains. If installed on different machines                      ##
##        it is necessary to modify the configuration manually.                                        ##
##        Fully automatic installation only requires a password change at the end if you want.         ##
##                                                                                                     ##
##Authors:                                                                                             ##
##			Manuel José Beiras Belloso																   ##
##			Rubén Míguez Bouzas										                                   ##
##			Luis Mera Castro										                                   ##
#########################################################################################################

# Initial check if the user is root and the OS is Ubuntu
function initialCheck() {
	if ! isRoot; then
		echo "The script must be executed as a root"
		exit 1
	fi
}

# Check if the user is root
function isRoot() {
    if [ "$EUID" -ne 0 ]; then
		return 1
	fi
	checkOS
}

# Check the operating system
function checkOS() {
    source /etc/os-release
	if [[ $ID == "ubuntu" ]]; then
	    OS="ubuntu"
	    MAJOR_UBUNTU_VERSION=$(echo "$VERSION_ID" | cut -d '.' -f1)
	    if [[ $MAJOR_UBUNTU_VERSION -lt 20 ]]; then
            echo "⚠️ This script it's not tested in your Ubuntu version. You want to continue?"
			echo ""
			CONTINUE='false'
			until [[ $CONTINUE =~ (y|n) ]]; do
			    read -rp "Continue? [y/n]: " -e CONTINUE
			done
			if [[ $CONTINUE == "n" ]]; then
				exit 1
			fi
		fi
		questionsMenu
	else
        echo "Your OS it's not Ubuntu, in the case you are using Centos you can continue from here. Press [Y]"
		CONTINUE='false'
		until [[ $CONTINUE =~ (y|n) ]]; do
			read -rp "Continue? [y/n]: " -e CONTINUE
		done
		if [[ $CONTINUE == "n" ]]; then
			exit 1
		fi
		OS="centos"
		questionsMenu
	fi
}

function questionsMenu() {
    echo -e "What you want to do ?"
	echo "1. Install Zabbix."
	echo "2. Uninstall Zabbix."
    echo "3. Uninstall Mysql."
    echo "4. Uninstall Everything. (Zabbix, Mysql)"
    echo "0. exit."
    read -e CONTINUE
    if [[ $CONTINUE == 1 ]]; then
        installZabbix
    elif [[ $CONTINUE == 2 ]]; then
        uninstallZabbix
    elif [[ $CONTINUE == 3 ]]; then
        uninstallMysql
    elif [[ $CONTINUE == 4 ]]; then
        uninstallAll
    elif [[ $CONTINUE == 0 ]]; then
        exit 1
    else
		echo "invalid option !"
		questionsMenu
	fi
}



function questionsMenu() {
	echo -e "What you want to do ?"
	echo "1. Install Zabbix."
	echo "2. Uninstall Zabbix."
	echo "0. exit."
	read -e CONTINUE
	if [[ $CONTINUE == 1 ]]; then
		installZabbix
	elif [[ $CONTINUE == 2 ]]; then
		uninstallZabbix
	elif [[ $CONTINUE == 0 ]]; then
		exit 1
	else
		echo "invalid option !"
		clear
		questionsMenu
	fi
}

function installZabbix() {
    if [[ $OS == "ubuntu" ]]; then
        if dpkg -l | grep zabbix > /dev/null; then
            echo "Zabbix it's already installed on your system."
            echo "Installation cancelled."
        else
            # We download the repository, add it with the package manager and update the list of team repositories.
            wget https://repo.zabbix.com/zabbix/5.0/ubuntu/pool/main/z/zabbix-release/zabbix-release_5.0-1+focal_all.deb
            dpkg -i zabbix-release_5.0-1+focal_all.deb
            apt update -y
            QuestionsDB
        fi
    fi
}

function QuestionsDB {
    echo "To continue we need to install a database."
    echo "1. MySQL."
    echo "2. PostgreSQL."
    echo "3. Back to the main menu."
    read -e $CONTINUE
    if [[ $CONTINUE == 1 ]]; then
        InstallMysql
    elif [[ $CONTINUE == 2 ]]; then
        installPostgresql
    elif [[ $CONTINUE == 3 ]]; then
        questionsMenu
    else
        echo "invalid option !"
        QuestionsDB
    fi
}

function InstallMysql() {
    if [[ $OS == "ubuntu" ]]; then
        if dpkg -l | grep mariadb > /dev/null; then
            echo "Mysql it's already installed on your system."
            echo "Installation cancelled."
        else
            apt -y update && apt -y upgrade && apt -y install software-properties-common
            ## Add PGP key of mariadb.
            apt-key adv --fetch-keys 'https://mariadb.org/mariadb_release_signing_key.asc'
            add-apt-repository 'deb [arch=amd64] http://mariadb.mirror.globo.tech/repo/10.5/ubuntu focal main'
            apt -y update && apt -y upgrade
            # Install mariadb.
            apt -y install mariadb-server mariadb-client
            # Restart service to fix error: ERROR 2002 (HY000): Can't connect to local MySQL server through socket '/run/mysqld/mysqld.sock' (2)
            service mariadb restart
            echo ""
            echo ""
            echo "We automate mysql_secure_installation, user: root, password: abc123., never show username or password production. Just test pourpose."
            echo ""
            echo ""
            # Change the root password?
            mysql -e "SET PASSWORD FOR root@localhost = PASSWORD('abc123.');FLUSH PRIVILEGES;"
            # Remove anonymous users
            mysql -e "DELETE FROM mysql.user WHERE User='';"
            # Disallow root login remotely?
            mysql -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
            # Remove test database and access to it?
            mysql -e "DROP DATABASE test;DELETE FROM mysql.db WHERE Db='test' OR Db='test_%';"
            # Reload privilege tables now?
            mysql -e "flush privileges;"
            # We install the server backend, frontend and agent to monitor the server.
            apt -y install zabbix-server-mysql zabbix-frontend-php zabbix-apache-conf zabbix-agent
            echo "!!!abc123. password!!!"
            echo "Create zabbix database."
            mysql -u root -p -e "CREATE DATABASE zabbix character set utf8 collate utf8_bin;"
            echo "Create zabbix user."
            mysql -u root -p -e "create user zabbix@localhost identified by 'abc123.';"
            echo "Give the necessary permissions."
            mysql -u root -p -e "grant all privileges on zabbix.* to zabbix@localhost;"
            echo "Generate the initial schema of the DB to be used by the Zabbix server."
            zcat /usr/share/doc/zabbix-server-mysql*/create.sql.gz | mysql -u zabbix -p zabbix
            # We define the DB password in the Zabbix configuration files.
            sed -i 's|# DBPassword=|DBPassword=abc123.|' /etc/zabbix/zabbix_server.conf
            # We set the server timezone for our frontend.
            sed -i '20s|.*|        php_value date.timezone Europe/Madrid|' /etc/zabbix/apache.conf
            sed -i '30s|.*|        php_value date.timezone Europe/Madrid|' /etc/zabbix/apache.conf
            # We fix the problems with php by making a loop that detects all php versions and edits them.
            for i in $(ls /etc/php/);do
                sed -i '973s|.*|date.timezone = Europe/Madrid|' /etc/php/$i/apache2/php.ini
                sed -i 's|post_max_size = 8M|post_max_size = 16M|' /etc/php/$i/apache2/php.ini
                sed -i 's|max_execution_time = 30|max_execution_time = 300|' /etc/php/$i/apache2/php.ini
                sed -i 's|max_input_time = 60|max_input_time = 300|' /etc/php/$i/apache2/php.ini
            done
            chown root:root /var/run/zabbix/zabbix_agentd.pid
            chown root:root /var/run/zabbix/zabbix_server.pid
            chmod 644 /var/run/zabbix/zabbix_agentd.pid
            chmod 644 /var/run/zabbix/zabbix_server.pid
            service apache2 start
            service zabbix-server start
            service zabbix-agent start
            systemctl enable zabbix-server zabbix-agent apache2
            echo ""
            echo ""
            echo "Zabbix installed successfully."
            echo ""
            echo ""
            questionsMenu
        fi
    fi
}

function installPostgresql() {
    echo "Work in progress."
    questionsMenu
}

function uninstallZabbix() {
    apt -y remove zabbix-server-mysql zabbix-frontend-php zabbix-apache-conf zabbix-agent
    apt -y purge zabbix-server-mysql zabbix-frontend-php zabbix-apache-conf zabbix-agent
    apt -y remove zabbix-*
    apt -y purge zabbix-*
    apt -y autoremove
    apt -y autoclean
    echo ""
    echo ""
    echo ""
    echo "Zabbix uninstalled."
    echo ""
    echo ""
    echo ""
}

function uninstallMysql() {
    apt -y remove mariadb-server mariadb-client software-properties-common
    apt -y purge mariadb-server mariadb-client software-properties-common
    apt -y  purge mariadb-server-*
    apt -y  purge mariadb-server-10.3
    apt -y  purge mariadb-server-10.5
    apt -y  purge mariadb-client-*
    apt -y  purge mariadb-common
    apt -y autoremove
    apt -y autoclean
    echo ""
    echo ""
    echo ""
    echo "Mysql uninstalled."
    echo ""
    echo ""
    echo ""
}

function uninstallAll() {
    chown root:root /var/run/zabbix/zabbix_agentd.pid
    chown root:root /var/run/zabbix/zabbix_server.pid
    chmod 644 /var/run/zabbix/zabbix_agentd.pid
    chmod 644 /var/run/zabbix/zabbix_server.pid
    apt -y remove zabbix-server-mysql zabbix-frontend-php zabbix-apache-conf zabbix-agent zabbix-release
    apt -y purge zabbix-server-mysql zabbix-frontend-php zabbix-apache-conf zabbix-agent zabbix-release
    apt -y remove zabbix-*
    apt -y purge zabbix-*
    apt -y remove mariadb-server mariadb-client software-properties-common 
    apt -y purge mariadb-server mariadb-client software-properties-common
    apt -y  purge mariadb-server-*
    apt -y  purge mariadb-server-10.3
    apt -y  purge mariadb-server-10.5
    apt -y  purge mariadb-client-*
    apt -y  purge mariadb-common
    apt -y  remove php7.0-*
    apt -y  purge php7.0-*
    apt -y  remove php7.0-common
    apt -y  purge php7.0-common
    apt -y  remove php-common
    apt -y  purge php-common
    apt -y  remove libapache2-mod-php7.0
    apt -y  purge libapache2-mod-php7.0
    apt -y  remove libapache2-mod-php8.0 
    apt -y  purge libapache2-mod-php8.0 
    apt -y  remove php-pear
    apt -y  purge php-pear
    apt -y  remove php8.0-*
    apt -y  purge php8.0-*
    apt -y autoremove
    apt -y autoclean
    echo ""
    echo ""
    echo ""
    echo "All uninstalled."
    echo ""
    echo ""
    echo ""
}

initialCheck