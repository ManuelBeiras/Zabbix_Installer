#!/bin/bash
#########################################################################################################
##Script de instalación de Zabbix 											                           ##
##Fecha: 14/10/2021                                                                                    ##
##Versión 1.0:  Permite la instalacion simple de Zabbix.							                   ##
##        Si la instalación de todos los componentes se hace en una misma máquina                      ##
##        queda una versión completamente operativa. Si se instala en diferentes máquinas              ##
##        es necesario modificar la configuración manualmente.                                         ##
##                                                                                                     ##
##Autores:                                                                                             ##
##			Manuel José Beiras Belloso																   ##
##			Rubén Míguez Bouzas										                                   ##
##			Luis Mera Castro										                                   ##
#########################################################################################################

# Comprobación inicial que valida si se es root y si el sistema operativo es Ubuntu
function initialCheck() {
	if ! isRoot; then
		echo "El script tiene que ser ejecutado como root"
		exit 1
	fi
}

# Funcion que comprueba que se ejecute el script como root
function isRoot() {
	if [ "$EUID" -ne 0 ]; then
		return 1
	fi
	checkOS
}

function checkOS() {
	source /etc/os-release
	if [[ $ID == "ubuntu" ]]; then
		OS="ubuntu"
		MAJOR_UBUNTU_VERSION=$(echo "$VERSION_ID" | cut -d '.' -f1)
		if [[ $MAJOR_UBUNTU_VERSION -lt 20 ]]; then
			echo "⚠️ Este script no está probado en tu versión de Ubuntu. ¿Deseas continuar?"
			echo ""
			CONTINUAR='false'
			until [[ $CONTINUAR =~ (y|n) ]]; do
				read -rp "Continuar? [y/n]: " -e CONTINUAR
			done
			if [[ $CONTINUAR == "n" ]]; then
				exit 1
			fi
		fi
		preguntasInstalacion
	else
		echo "Tu sistema operativo no es Ubuntu, en caso de que sea Centos puedes continuar desde aquí. Pulsa [Y]"
		CONTINUAR='false'
		until [[ $CONTINUAR =~ (y|n) ]]; do
			read -rp "Continuar? [y/n]: " -e CONTINUAR
		done
		if [[ $CONTINUAR == "n" ]]; then
			exit 1
		fi
		OS="centos"
		preguntasInstalacion
	fi
}

function preguntasInstalacion() {
    echo -e "Qué deseas hacer?"
	echo "1. Instalar Zabbix."
	echo "2. Desinstalar Zabbix."
    echo "3. Desinstalar Mysql."
    echo "4. Desinstalar Todo. (Zabbix, Mysql)"
    echo "5. salir."
    read -e CONTINUAR
    if [[ CONTINUAR -eq 1 ]]; then
        instalarZabbix
    elif [[ CONTINUAR -eq 2 ]]; then
        desinstalarZabbix
    elif [[ CONTINUAR -eq 3 ]]; then
        desinstalarMysql
    elif [[ CONTINUAR -eq 4 ]]; then
        desinstalarTodo
    elif [[ CONTINUAR -eq 5 ]]; then
        exit 1
    else
		echo "Opcion no válida!"
		preguntasInstalacion
	fi
}

function instalarZabbix() {
    if [[ $OS == "ubuntu" ]]; then
        if dpkg -l | grep zabbix > /dev/null; then
            echo "Zabbix ya está instalado en tu sistema."
            echo "No se continúa con la instalación."
        else
            # Descargamos el repositorio, lo añadimos con el administrador de paquetes y actualizamos la lista de repositorios del equipo
            wget https://repo.zabbix.com/zabbix/5.0/ubuntu/pool/main/z/zabbix-release/zabbix-release_5.0-1+focal_all.deb
            dpkg -i zabbix-release_5.0-1+focal_all.deb
            apt update -y
            preguntasBD
        fi
    fi
}

function preguntasBD {
    echo "Para continuar tiene que instalar una base de datos."
    echo "1. MySQL."
    echo "2. PostgreSQL."
    echo "3. Volver al menú principal."
    read -e CONTINUAR
    if [[ CONTINUAR -eq 1 ]]; then
        instalarMysql
    elif [[ CONTINUAR -eq 2 ]]; then
        instalarPostgresql
    elif [[ CONTINUAR -eq 3 ]]; then
        preguntasInstalacion
    else
        echo "Opción no válida"
        preguntasBD
    fi
}

function instalarMysql() {
    if [[ $OS == "ubuntu" ]]; then
        if dpkg -l | grep mariadb > /dev/null; then
            echo "Mysql ya está instalado en tu sistema."
            echo "No se continúa con la instalación."
        else
            apt -y update && apt -y upgrade && apt -y install software-properties-common
            ## Añadimos clave PGP de mariadb.
            apt-key adv --fetch-keys 'https://mariadb.org/mariadb_release_signing_key.asc'
            # Este comando necesita software-properties-common instalado.
            add-apt-repository 'deb [arch=amd64] http://mariadb.mirror.globo.tech/repo/10.5/ubuntu focal main'
            apt -y update && apt -y upgrade
            # Instalamos mariadb.
            apt -y install mariadb-server mariadb-client
            # Reiniciamos servicio para arreglar error: ERROR 2002 (HY000): Can't connect to local MySQL server through socket '/run/mysqld/mysqld.sock' (2)
            service mariadb restart
            echo ""
            echo ""
            echo "Automatizamos mysql_secure_installation, usuario: root, password: abc123., nunca mostar usuario ni contraseña producción. Solo prueba."
            echo ""
            echo ""
            ## Automatizamos mysql_secure_installation via comandos.
            ## Mirar como mejorar.
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
            # Instalamos el backend del servidor, el frontend y el agente para monitorizar el servidor.
            apt -y install zabbix-server-mysql zabbix-frontend-php zabbix-apache-conf zabbix-agent
            echo "!!!abc123. contraseña!!!"
            echo "Creamos base de datos zabbix."
            mysql -u root -p -e "CREATE DATABASE zabbix character set utf8 collate utf8_bin;"
            echo "Creamos usuario zabbix."
            mysql -u root -p -e "create user zabbix@localhost identified by 'abc123.';"
            echo "Damos los permisos necesarios."
            mysql -u root -p -e "grant all privileges on zabbix.* to zabbix@localhost;"
            echo "Generamos el initial schema de la BBDD que usará el servidor Zabbix."
            zcat /usr/share/doc/zabbix-server-mysql*/create.sql.gz | mysql -u zabbix -p zabbix
            # Definimos la contraseña de la BBDD en los ficheros de configuración de Zabbix.
            sed -i 's|# DBPassword=|DBPassword=abc123.|' /etc/zabbix/zabbix_server.conf
            # Establecemos la zona horaria del servidor para nuestro frontend.
            sed -i '20s|.*|        php_value date.timezone Europe/Madrid|' /etc/zabbix/apache.conf
            sed -i '30s|.*|        php_value date.timezone Europe/Madrid|' /etc/zabbix/apache.conf
            # Fixeamos los problemas con php haciendo un bucle que detecta todas las versiones de php y las edita.
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
            echo "Zabbix instalado correctamente."
            echo ""
            echo ""
            preguntasInstalacion
        fi
    fi
}

function instalarPostgresql() {
    echo "No está hecho. Está en proceso."
    preguntasInstalacion
}

function desinstalarZabbix() {
    apt -y remove zabbix-server-mysql zabbix-frontend-php zabbix-apache-conf zabbix-agent
    apt -y purge zabbix-server-mysql zabbix-frontend-php zabbix-apache-conf zabbix-agent
    apt -y remove zabbix-*
    apt -y purge zabbix-*
    apt -y autoremove
    apt -y autoclean
    echo ""
    echo ""
    echo ""
    echo "Zabbix desinstalado."
    echo ""
    echo ""
    echo ""
}

function desinstalarMysql() {
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
    echo "Mysql desinstalado."
    echo ""
    echo ""
    echo ""
}

function desinstalarTodo() {
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
    echo "Todo desinstalado."
    echo ""
    echo ""
    echo ""
}

initialCheck