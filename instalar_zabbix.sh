#!/bin/bash

# Comprobación inicial que valida si se es root y si el sistema operativo es Ubutu
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
	echo "1. Instalar Grafana."
	echo "2. Desinstalar Grafana."
    echo "3. salir."
    read -e CONTINUAR
    if [[ CONTINUAR -eq 1 ]]; then
        instalarGrafana
    elif [[ CONTINUAR -eq 2 ]]; then
        desinstalarGrafana
    elif [[ CONTINUAR -eq 3 ]]; then
        exit 1
    else
		echo "Opcion no válida!"
		preguntasInstalacion
	fi
}

function instalarGrafana() {
    if [[ $OS == "ubuntu" ]]; then
        if dpkg -l | grep grafana > /dev/null; then
            echo "Grafana ya está instalado en tu sistema."
            echo "No se continúa con la instalación."
        else
            # Se instalan los requisitos previos y se añade la clave del repositorio.
			apt install -y apt-transport-https
			apt install -y software-properties-common wget
			wget -q -O - https://packages.grafana.com/gpg.key | apt-key add -
			# Añadimos repositorio al sources list.
			echo "deb https://packages.grafana.com/oss/deb stable main" | tee -a /etc/apt/sources.list.d/grafana.list
			apt -y update
			# Instalamos grafana
			apt install -y grafana
			systemctl daemon-reload
			service grafana-server start
			sudo systemctl enable grafana-server.service
			preguntasPluginZabbix
        fi
    fi
}

function preguntasPluginZabbix() {
    echo "Quieres instalar el plugin de zabbix si tienes un zabbix instalado ?"
    echo "1. Si."
    echo "2. Volver menú principal."
    read -e CONTINUAR
    if [[ CONTINUAR -eq 1 ]]; then
        instalarPluginZabbix
    elif [[ CONTINUAR -eq 2 ]]; then
        preguntasInstalacion
    else
        echo "Opción no válida"
    fi
}

function instalarPluginZabbix() {
	grafana-cli plugins list-remote
	grafana-cli plugins install alexanderzobnin-zabbix-app
	sed -i 's|allow_loading_unsigned_plugins =|allow_loading_unsigned_plugins = alexanderzobnin-zabbix-datasource|' /usr/share/grafana/conf/defaults.ini 
	service grafana-server restart
	echo ""
    echo ""
    echo ""
    echo "Plugin de zabbix para Grafana instalado correctamente."
    echo ""
    echo ""
    echo ""
}

function desinstalarGrafana() {
    apt -y remove grafana
    apt -y purge grafana
    apt -y autoremove
    apt -y autoclean
	rm -r /etc/grafana/
	rm -r /var/lib/grafana/
    echo ""
    echo ""
    echo ""
    echo "Grafana desinstalado."
    echo ""
    echo ""
    echo ""
}

initialCheck