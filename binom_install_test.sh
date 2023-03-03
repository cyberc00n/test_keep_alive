#!/bin/bash
# This script install the Binom tracker and all software that is needed
#
# Copyright (C) 2016-2022 Binom Support Team

version=v3.989

log_file="/var/log/binom/binom_1click.log"
log_file_temp="/tmp/binom_temp.log"

ioncube_version=10.4.5

log () {
    echo "- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -" >> "${log_file}"
    echo "$(date '+%d-%m-%Y %H:%M:%S') $1" >> "${log_file}"
    if [[ -n $2 ]]; then
        echo "$1"
    fi
}

read_variable () {
    variable="$1"
    text="$2"
    while [[ -z "${!variable}" ]]
    do
        echo "
${text} "
        read -r "${variable?}"
        log "$2 ${!variable}"
        case $1 in
            "domain")
                temp="${!variable}"
                # Do not touch "\-" in the end of grep!
                temp_=$(echo "${temp}" | grep -o '[a-zA-Z0-9\_\@\ \t\.\-]' | tr -d '\n' | grep -Ev '\.{2,99}')
                ;;
            "dmains")
            # Delete empty symbols between domains if domains > 1
                temp=$(sed -E 's/[ \t]*//g' <<< "${!variable}")
                # Do not touch "\-" in the end of grep!
                temp_=$(echo "${temp}" | grep -o '[a-zA-Z0-9\_\@\ \t\.\-]' | tr -d '\n' | grep -Ev '\.{2,99}')
                ;;
            "user_email")
                temp="${!variable}"
                # Do not touch "\-" in the end of grep!
                temp_=$(echo "${temp}" | grep -Eo '\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,15}\b' | tr -d '\n')
                ;;
            *)
                temp="${!variable}"
                temp_=$(echo "${!variable}" | grep -o '[a-zA-Z0-9\_\@\.\-]' | tr -d '\n')
                ;;
        esac
        if ! [[ "${temp_}" == "${temp}" ]]; then
            echo "You can use only these symbols: a-Z 0-9 . - _ @"
            eval "${variable}"=''
        fi
    done
}

check_os () {
    if [ -f /etc/os-release ]; then
        case $(grep -E "(ID=debian|ID=ubuntu)" /etc/os-release | sed 's/ID=//') in
            debian)
                os_type="debian"
                case $(cat /etc/debian_version) in
                    #11*)
                    #    os_version="bullseye"
                    #    ;;
                    10*)
                        os_version="buster"
                        ;;
                    *)
                        echo "


    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    !!!!!!!!! W A R N I N G !!!!!!!!!!!
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

    1Click can be used with Debian, 
    but only this versions:
        - 10.x

    "
                        exit 1
                        ;;
                esac
                ;;
            ubuntu)
                os_type="ubuntu"
                case $(grep DISTRIB_CODENAME /etc/lsb-release | sed 's/DISTRIB_CODENAME=//') in
                    bionic)
                        os_version="bionic";;
                    focal)
                        os_version="focal";;
                    *)
                        echo "


    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    !!!!!!!!! W A R N I N G !!!!!!!!!!!
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

    1Click can be used with Ubuntu, 
    but only these versions:
        - 18.04.x
        - 20.04.x
    
    "
                        exit;;
                esac
                ;;
            *)
                echo "


    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    !!!!!!!!! W A R N I N G !!!!!!!!!!!
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

    Debian or Ubuntu is not found :(

    Please check your OS, this 1Click can 
    be used only with 
        - Debian 10.x
        - Ubuntu 18.04.x / 20.04.x


    "
                exit 1    
                ;;    
        esac
    else
        echo "


    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    !!!!!!!!! W A R N I N G !!!!!!!!!!!
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

    Debian or Ubuntu is not found :(

    Please check your OS, this 1Click can 
    be used only with 
        - Debian 10.x
        - Ubuntu 18.04.x / 20.04.x


    "
        exit 1    
    fi    
}

get_ppa () {
    if ! [ -f /etc/apt/sources.list.d/ppa.launchpad.net-php.list ]; then
        log "Installing PPA repo.." "+"
        case ${os_type} in
            debian)
                apt-get -y install apt-transport-https >> "${log_file}" 2>&1
                wget -O /usr/share/keyrings/deb.sury.org-php.gpg https://packages.sury.org/php/apt.gpg >> "${log_file}" 2>&1
                echo "deb [signed-by=/usr/share/keyrings/deb.sury.org-php.gpg] https://packages.sury.org/php/ ${os_version} main" >> /etc/apt/sources.list.d/ppa.launchpad.net-php.list
                ;;
            ubuntu)
                apt-get -y install software-properties-common dirmngr >> "${log_file}" 2>&1
                echo "deb http://ppa.launchpad.net/ondrej/php/ubuntu ${os_version} main
deb-src http://ppa.launchpad.net/ondrej/php/ubuntu ${os_version} main" >> /etc/apt/sources.list.d/ppa.launchpad.net-php.list
                check_ppa_key=$(tail -n 1 "${log_file}" | grep "imported: 1")
                # Fix of server error
                while [[ -z ${check_ppa_key} ]]; do
                    apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 14AA40EC0831756756D7F66C4F4EA0AAE5267A6C >> "${log_file}" 2>&1
                    apt-key export 14AA40EC0831756756D7F66C4F4EA0AAE5267A6C 2>/dev/null | grep "PUBLIC" >> "${log_file}" 2>/dev/null
                    check_ppa_key=$(tail -n 1 "${log_file}" | grep "PUBLIC")
                    sleep 5
                done
                ;;
        esac
        apt-get update >> "${log_file}" 2>&1
        check_exit
    else
        log "Installing PPA repo - already installed" "+"
    fi
    check_exit
}

get_percona () {
    #sources_list_percona=`dpkg -l *server* | grep ii | grep percona-server-server | awk {'print $2,$3'}`
    if ! check_installed percona-server-server-5.7; then
        log "Installing Percona Server.." "+"
        if [[ $(check_download "https://repo.percona.com/apt/percona-release_latest.${os_version}_all.deb" 'percona.deb' 'exit') == 1 ]]; then
            wget https://repo.percona.com/apt/percona-release_latest."${os_version}"_all.deb >> "${log_file}" 2>&1
        fi
        {
            dpkg -i percona-release_latest."${os_version}"_all.deb
            rm percona-release_latest."${os_version}"_all.deb
            apt-get update
        } >> "${log_file}" 2>&1
        mysql_pass=$(pass_generator 16)
        export DEBIAN_FRONTEND=noninteractive
        apt-get install -y percona-server-server-5.7 >> "${log_file}" 2>&1

        # Manual package installing if Percona repo is not working

        #apt install -y mysql-common libjemalloc1 libaio1 libmecab2 debsums libatomic1 libsasl2-2 psmisc >> "${log_file}" 2>&1
        #case $os_type in
        #    debian)
        #        apt install -y libcurl3 >> "${log_file}" 2>&1
        #        ;;
        #    ubuntu)
        #        apt install -y libcurl4 >> "${log_file}" 2>&1
        #        ;;
        #esac
        #percona_version=5.7_5.7.28-31-1
        #wget https://www.percona.com/downloads/Percona-Server-5.7/Percona-Server-5.7.25-28/binary/debian/${os_version}/x86_64/percona-server-common-${percona_version}.${os_version}_amd64.deb -O /tmp/percona-server-common-${percona_version}.${os_version}_amd64.deb >> "${log_file}" 2>&1
        #dpkg -i /tmp/percona-server-common-${percona_version}.${os_version}_amd64.deb >> "${log_file}" 2>&1
        #rm /tmp/percona-server-common-${percona_version}.${os_version}_amd64.deb >> "${log_file}" 2>&1
        #wget https://www.percona.com/downloads/Percona-Server-5.7/Percona-Server-5.7.25-28/binary/debian/${os_version}/x86_64/percona-server-client-${percona_version}.${os_version}_amd64.deb -O /tmp/percona-server-client-${percona_version}.${os_version}_amd64.deb >> "${log_file}" 2>&1
        #dpkg -i /tmp/percona-server-client-${percona_version}.${os_version}_amd64.deb >> "${log_file}" 2>&1
        #rm /tmp/percona-server-client-${percona_version}.${os_version}_amd64.deb >> "${log_file}" 2>&1
        #wget https://www.percona.com/downloads/Percona-Server-5.7/Percona-Server-5.7.25-28/binary/debian/${os_version}/x86_64/percona-server-server-${percona_version}.${os_version}_amd64.deb -O /tmp/percona-server-server-${percona_version}.${os_version}_amd64.deb >> "${log_file}" 2>&1
        #mysql_pass=$(pass_generator 16)
        #export DEBIAN_FRONTEND=noninteractive
        #dpkg -i /tmp/percona-server-server-${percona_version}.${os_version}_amd64.deb >> "${log_file}" 2>&1
        #rm /tmp/percona-server-server-${percona_version}.${os_version}_amd64.deb >> "${log_file}" 2>&1
        check_exit
        if ! check_installed percona-server-server-5.7; then
            echo ""
            log "You have some problems with installing MySQL." "+"
            echo "Please contact Binom Support (support.binom.org)"
            echo ""
            exit 1
        fi
        check_mysql
        # Debain 7 fix
        sleep 10
        mysql -uroot -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${mysql_pass}';" >> "${log_file}" 2>&1
        echo "[client]
user=root
password=${mysql_pass}" > /root/.my.cnf
        chmod 600 /root/.my.cnf
    else
        log "Installing Percona Server - already installed" "+"
    fi
}

get_nginx () {
    if ! [ -f /etc/apt/sources.list.d/nginx.list ]; then
        log "Installing Nginx repo.." "+"
        {
            wget https://nginx.org/keys/nginx_signing.key
            apt-key add nginx_signing.key
            rm nginx_signing.key
        } >> "${log_file}" 2>&1
        echo "deb http://nginx.org/packages/${os_type}/ ${os_version} nginx
deb-src http://nginx.org/packages/${os_type}/ ${os_version} nginx" >> /etc/apt/sources.list.d/nginx.list
        apt-get update >> "${log_file}" 2>&1
    else
        log "Installing Nginx repo - already installed" "+"
    fi
    if ! [ -d /etc/nginx/sites-available ]; then
        mkdir -p /etc/nginx/sites-available
    fi
    if ! [ -d /etc/nginx/sites-enabled ]; then
        mkdir -p /etc/nginx/sites-enabled
    fi
}

free_space_check () {
    if [[ -f "${check_space_folder}/binom_check_space.sh" ]]; then
        rm -f "${check_space_folder}/binom_check_space.sh" >> "${log_file}" 2>&1
    fi
    wget -P "${check_space_folder}" "https://s3.eu-central-1.amazonaws.com/data.binom.org/check-space/binom_check_space.sh" >> "${log_file}" 2>&1
    chmod 700 "${check_space_folder}/binom_check_space.sh"
    cron=$(grep "binom_check_space.sh" /etc/crontab)
    if [[ -z "${cron}"  && ! -f /etc/cron.d/binom ]]; then
        if [[ -d  /etc/cron.d ]]; then
            echo "
##############################################################################################

# This script will be checking free space on your server every hour / after reboot
# and sending this info to Binom's folder in .../configuration/check_space.php file

################################################################################## Binom.org #

0 * * * *     root    bash ${check_space_folder}/binom_check_space.sh
@reboot         root    bash ${check_space_folder}/binom_check_space.sh
" >> /etc/cron.d/binom
                    service cron restart >> "${log_file}" 2>&1
                else
                    echo "Error! /etc/cron.d/ is not found!"
                    echo ""
            fi
    fi
}

check_installed () {
    local package=$1
    local return_str
    return_str=$(dpkg-query --showformat='${db:Status-Abbrev}\n' --show "${package}" 2> /null)
    if [[ "$return_str" =~ ^ii ]]; then
        log "Checking package ${package} - Installed"
        return 0
    else
        log "Checking package ${package} - Not installed"
        return 1
    fi
}

check_and_install () {
    local package=''
    for package in "${depends[@]}"
    do
        if ! check_installed "${package}"; then
            log "Installing ${package}.." "+"
            apt-get install -y "${package}" >> "${log_file}" 2>&1
            check_exit
            if ! check_installed "${package}"; then
                echo ""
                log "You have some problems with installing ${package}." "+"
                echo ""
                exit 1
            fi
        else
            log "Installing ${package} - already installed" "+"
        fi
    done
}

get_config_nginx () {
    log "Updating Nginx config.." "+"
    {
        rm -f /etc/nginx/nginx.conf
        wget -P /etc/nginx "https://s3.eu-central-1.amazonaws.com/data.binom.org/config/nginx/nginx.conf"
        service nginx restart
    } >> "${log_file}" 2>&1
}

get_config_php () {
    log "Updating PHP configs.." "+"
    rm -f "${php_path}/fpm/pool.d/www.conf" >> "${log_file}" 2>&1
    wget -P "${php_path}/fpm/pool.d" "${fpm_config}" >> "${log_file}" 2>&1

    #Some Binom tuning math for PHP-FPM
    if [[ -z "${total_ram}" ]]; then
        sed -i 's/HELLO_CHILDREN/20/' "${php_path}/fpm/pool.d/www.conf" >> "${log_file}" 2>&1
        sed -i 's/HELLO_BACKLOG/10/' "${php_path}/fpm/pool.d/www.conf" >> "${log_file}" 2>&1
    else
        php_children=$((total_ram / 99))
        if (("php_children" < "700")); then
            sed -i 's/'HELLO_CHILDREN'/'"${php_children}"'/' "${php_path}/fpm/pool.d/www.conf" >> "${log_file}" 2>&1
        else
            sed -i 's/HELLO_CHILDREN/700/' "${php_path}/fpm/pool.d/www.conf" >> "${log_file}" 2>&1
        fi
        php_backlog=$((php_children / 4 + 10))
        if (("php_backlog" < "250")); then
            sed -i 's/'HELLO_BACKLOG'/'"${php_backlog}"'/' "${php_path}/fpm/pool.d/www.conf" >> "${log_file}" 2>&1
        else
            sed -i 's/HELLO_BACKLOG/250/' "${php_path}/fpm/pool.d/www.conf" >> "${log_file}" 2>&1
        fi
    fi
    sed -i 's/'HELLO_PHP_VERSION'/'"${php_version}"'/' "${php_path}/fpm/pool.d/www.conf" >> "${log_file}" 2>&1
    php_ini_fpm=$(grep "Binom settings" "${php_path}/fpm/php.ini")
    if [[ -z "$php_ini_fpm" ]]; then
        {
            echo "; Binom settings"
            echo "post_max_size = 100M"
            echo "upload_max_filesize = 100M"
        } >> "${php_path}/fpm/php.ini"
    fi
    if ! [[ -d /var/run/php ]]; then
        mkdir /var/run/php >> "${log_file}" 2>&1
    fi
}

get_config_mysql () {
    log "Updating MySQL config.." "+"

    #We dont want to see mysql errors in syslog 
    if [[ -f "${mysql_path}/mysqld_safe_syslog.cnf" ]]; then
        rm -f "${mysql_path}/mysqld_safe_syslog.cnf" >> "${log_file}" 2>&1
    fi

    #Some Binom tuning math for MySQL
    if ! (("$total_ram" < "8192")); then
        if ! [[ -f "${mysql_path}/binom.cnf" ]]; then
            echo '!'"include ${mysql_path}/binom.cnf" >> /etc/mysql/my.cnf
            wget -P "${mysql_path}" "https://s3.eu-central-1.amazonaws.com/data.binom.org/config/mysql/binom.cnf" >> "${log_file}" 2>&1
            rm /var/lib/mysql/ib_logfile* >> "${log_file}" 2>&1
            cpu_threads_=$(grep -n 'processor' /proc/cpuinfo | grep -v 'KVM' | tail -n 1 | awk '{print $3}')
            cpu_threads=$((cpu_threads_ + 1 ))
            if (("$total_ram" < "4096")); then
                key_buffer_size=512
                bulk_insert_buffer_size=64
                myisam_sort_buffer_size=64
                read_buffer_size=64
                innodb_buffer_pool_size=515
                innodb_write_io_threads=$((cpu_threads * 2))
                innodb_read_io_threads=$((cpu_threads * 2))
                innodb_buffer_pool_instances=1
            else
                key_buffer_size=$((total_ram * 512 / 1950))
                bulk_insert_buffer_size=$((total_ram * 64 / 1950))
                myisam_sort_buffer_size=$((total_ram * 64 / 1950))
                read_buffer_size=$((total_ram * 64 / 1950))
                innodb_buffer_pool_size=$((total_ram * 512 / 1950))
                innodb_write_io_threads=$((cpu_threads * 2))
                innodb_read_io_threads=$((cpu_threads * 2))
                if (("$innodb_buffer_pool_size" < "1024")); then
                    innodb_buffer_pool_instances=1
                else
                    innodb_buffer_pool_instances=$((innodb_buffer_pool_size / 1000))
                fi
            fi
            echo "

[mysqld]
# Dynamic #

# Myisam #
key_buffer_size                     = ${key_buffer_size}M
bulk_insert_buffer_size             = ${bulk_insert_buffer_size}M
myisam_sort_buffer_size             = ${myisam_sort_buffer_size}M
read_buffer_size                    = ${read_buffer_size}M
 
# InnoDB #
innodb_buffer_pool_size             = ${innodb_buffer_pool_size}M
innodb_data_file_path               = ibdata1:10M:autoextend
innodb_write_io_threads             = ${innodb_write_io_threads}
innodb_read_io_threads              = ${innodb_read_io_threads}
innodb_buffer_pool_instances        = ${innodb_buffer_pool_instances}" >> "${mysql_path}/binom.cnf"
            fi
    else
        if ! [[ -f "${mysql_path}/binom-lite.cnf" ]]; then
            echo '!'"include ${mysql_path}/binom-lite.cnf" >> /etc/mysql/my.cnf
            cat <<'EOF' > "${mysql_path}/binom-lite.cnf"
[mysqld] 
skip-networking
sql_mode                            = ""
event_scheduler                     = ON
table_definition_cache              = 1600
max_sp_recursion_depth              = 3
max_heap_table_size                 = 2G
group_concat_max_len                = 20480
innodb_file_per_table               = 1
innodb_flush_log_at_trx_commit      = 2
query_cache_type                    = 0
query_cache_size                    = 0
concurrent_insert                   = 2
max_allowed_packet                  = 128M
log_error                           = /var/log/mysql/mysql_error.log
EOF
        fi
    fi
    # Too many open files fix
    mysql_d="/etc/systemd/system/mysql.service.d"
    if ! [[ -f "${mysql_d}/limits.conf" ]]; then
        mkdir -p "${mysql_d}" >> "${log_file}" 2>&1
        {
            echo "[Service]"
            echo "LimitNOFILE = infinity"
            echo "LimitMEMLOCK = infinity" 
        } >> "${mysql_d}/limits.conf"
        systemctl daemon-reload >> "${log_file}" 2>&1
    fi
    #Logrotate
    if [[ ! -f "/etc/logrotate.d/mysql" ]]; then
        cat <<'EOF' > /etc/logrotate.d/mysql
/var/log/mysql/*.log {
    create 644 mysql mysql
    notifempty
    weekly
    rotate 10
    missingok
    nocompress
    sharedscripts
    postrotate
        # run if mysqld is running
        if test -x /usr/bin/mysqladmin && /usr/bin/mysqladmin ping &>/dev/null; then
            mysqladmin flush-logs
        fi
    endscript
}
EOF
    fi
    service mysql stop >> "${log_file}" 2>&1
    if [[ -f /var/log/mysql/error.log ]]; then
        mv /var/log/mysql/error.log /var/log/mysql/mysql_error.log >> "${log_file}" 2>&1
    fi
    service mysql start >> "${log_file}" 2>&1
}

tracker_setup () {
    check_second_install
    if [[ -z "${user_email}" ]]; then
        read_variable user_email "Please enter your email:"
        echo ""
    fi
    if [[ -z "${timezone}" ]]; then
        echo "
Please choose your timezone:
        "
        PS3='
(for example, if you need GMT+3, enter 18)
Please enter your choice:
'
        case ${tracker_version} in
          Latest|1.13.007|1.15.108|1.16.009|1.17.024)
            options=( "GMT-12"
                      "GMT-11"
                      "GMT-10"
                      "GMT-9:30"
                      "GMT-9"
                      "GMT-8"
                      "GMT-7"
                      "GMT-6"
                      "GMT-5"
                      "GMT-4"
                      "GMT-3:30"
                      "GMT-3"
                      "GMT-2"
                      "GMT-1"
                      "GMT-0"
                      "GMT+1"
                      "GMT+2"
                      "GMT+3"
                      "GMT+3:30"
                      "GMT+4"
                      "GMT+4:30"
                      "GMT+5"
                      "GMT+5:30"
                      "GMT+5:45"
                      "GMT+6"
                      "GMT+6:30"
                      "GMT+7"
                      "GMT+8"
                      "GMT+8:45"
                      "GMT+9"
                      "GMT+10"
                      "GMT+10:30"
                      "GMT+11"
                      "GMT+12"
                      "GMT+12:45"
                      "GMT+13" )
            select opt in "${options[@]}"
            do
                case $opt in
                    "GMT-12")      timezone=-12:00;  break;;
                    "GMT-11")      timezone=-11:00;  break;;
                    "GMT-10")      timezone=-10:00;  break;;
                    "GMT-9:30")    timezone=-9:30;   break;;
                    "GMT-9")       timezone=-9:00;   break;;
                    "GMT-8")       timezone=-8:00;   break;;
                    "GMT-7")       timezone=-7:00;   break;;
                    "GMT-6")       timezone=-6:00;   break;;
                    "GMT-5")       timezone=-5:00;   break;;
                    "GMT-4")       timezone=-4:00;   break;;
                    "GMT-3")       timezone=-3:00;   break;;
                    "GMT-3:30")    timezone=-3:30;   break;;
                    "GMT-2")       timezone=-2:00;   break;;
                    "GMT-1")       timezone=-1:00;   break;;
                    "GMT-0")       timezone=+0:00;   break;;
                    "GMT+1")       timezone=+1:00;   break;;
                    "GMT+2")       timezone=+2:00;   break;;
                    "GMT+3")       timezone=+3:00;   break;;
                    "GMT+3:30")    timezone=+3:30;   break;;
                    "GMT+4")       timezone=+4:00;   break;;
                    "GMT+4:30")    timezone=+4:30;   break;;
                    "GMT+5")       timezone=+5:00;   break;;
                    "GMT+5:30")    timezone=+5:30;   break;;
                    "GMT+5:45")    timezone=+5:45;   break;;
                    "GMT+6")       timezone=+6:00;   break;;
                    "GMT+6:30")    timezone=+6:30;   break;;
                    "GMT+7")       timezone=+7:00;   break;;
                    "GMT+8")       timezone=+8:00;   break;;
                    "GMT+8:45")    timezone=+8:45;   break;;
                    "GMT+9")       timezone=+9:00;   break;;
                    "GMT+10")      timezone=+10:00;  break;;
                    "GMT+10:30")   timezone=+10:30;  break;;
                    "GMT+11")      timezone=+11:00;  break;;
                    "GMT+12")      timezone=+12:00;  break;;
                    "GMT+12:45")   timezone=+12:45;  break;;
                    "GMT+13")      timezone=+13:00;  break;;
                       *) echo "Choose timezone, please!";;
                esac
            done
            ;;
          *)
            options=("GMT-12" "GMT-11" "GMT-10" "GMT-9" "GMT-8" "GMT-7" "GMT-6" "GMT-5" "GMT-4" "GMT-3" "GMT-2" "GMT-1" "GMT-0" "GMT+1" "GMT+2" "GMT+3" "GMT+4" "GMT+5" "GMT+6" "GMT+7" "GMT+8" "GMT+9" "GMT+10" "GMT+11" "GMT+12")
            select opt in "${options[@]}"
            do
              case $opt in
                    "GMT-12")    timezone=-12;  break;;
                    "GMT-11")    timezone=-11;  break;;
                    "GMT-10")    timezone=-10;  break;;
                    "GMT-9")     timezone=-9;   break;;
                    "GMT-8")     timezone=-8;   break;;
                    "GMT-7")     timezone=-7;   break;;
                    "GMT-6")     timezone=-6;   break;;
                    "GMT-5")     timezone=-5;   break;;
                    "GMT-4")     timezone=-4;   break;;
                    "GMT-3")     timezone=-3;   break;;
                    "GMT-2")     timezone=-2;   break;;
                    "GMT-1")     timezone=-1;   break;;
                    "GMT-0")     timezone=0;    break;;
                    "GMT+1")     timezone=1;    break;;
                    "GMT+2")     timezone=2;    break;;
                    "GMT+3")     timezone=3;    break;;
                    "GMT+4")     timezone=4;    break;;
                    "GMT+5")     timezone=5;    break;;
                    "GMT+6")     timezone=6;    break;;
                    "GMT+7")     timezone=7;    break;;
                    "GMT+8")     timezone=8;    break;;
                    "GMT+9")     timezone=9;    break;;
                    "GMT+10")    timezone=10;   break;;
                    "GMT+11")    timezone=11;   break;;
                    "GMT+12")    timezone=12;   break;;
                       *) echo "Choose timezone, please!";;
              esac
            done
            ;;
        esac
    fi
    log "Timezone: ${timezone}"
    if [[ -n "${db_name}" ]]; then
        read_variable db_name "Please, enter name for database:" 
    else
        db_name=binom
    fi
}

download_and_unpack () {
    mkdir -p "${files_path}${subfolder}" >> "${log_file}" 2>&1
    log "Downloading ${tracker_version} Binom.." "+"
    {
        wget -P "${files_path}${subfolder}" "${tracker_download}"
        tar -xzf "${files_path}${subfolder}"/*.tar.gz -C "${files_path}${subfolder}"
        rm "${files_path}${subfolder}"/*.tar.gz
    } >> "${log_file}" 2>&1
    
    if [[ -z "${user_pass}" ]]; then
        user_pass=$(pass_generator 8)
    fi
    if [[ -z "${mysql_pass}" ]]; then
        mysql_pass
    fi

    database_exist="$(mysql -uroot -p"${mysql_pass}" -e "show databases;" 2>> "${log_file}" | grep "${db_name}")"
    if [[ -n "${database_exist}" ]]; then
        echo ""
        echo "Warning!"
        log "It seems you have old tracker database (${db_name}) on disk." "+"
        PS3='
Please enter your choice:
'
        options=("Delete old database and create a new one instead." "Do not touch old database and create new one.")
        select opt in "${options[@]}"
        do
            case $opt in
                "Delete old database and create a new one instead.")
                    break
                      ;;
                "Do not touch old database and create new one.")
                    db_name_old="${db_name}"
                    while [[ "${db_name}" == "${db_name_old}"  ]]; do
                        db_name=''
                        read_variable db_name "Enter new database name:"
                        log "Try database name: ${db_name}"
                    done
                    break
                      ;;
                 *)
                    echo "
Enter 1 or 2
"
                    ;;
            esac
        done
        log "New database name: ${db_name}"
    fi
    if ! [[ -f "${files_path}${subfolder}/index.php" ]]; then
        echo ""
        echo "Tracker files are not found."
        echo ""
        exit 1
    fi
    si_check on
    mt_threads=$(grep -c 'processor' < /proc/cpuinfo)
    if [[ -z "${subfolder}" ]]; then
        tracker_settings='{"type_install":"auto","db_host":"localhost","db_user":"root","db_pass":"'${mysql_pass}'","db_name":"'${db_name}'","mail":"'${user_email}'","user":"root","pass":"'${user_pass}'","timezone":"'${timezone}'","si":"'${si}'","mt_threads":"'${mt_threads}'","link":"'${http_type}':\/\/'${domain}'\/"}'
    else
        subfolder_="\\${subfolder}" #lint needs
        tracker_settings='{"type_install":"auto","db_host":"localhost","db_user":"root","db_pass":"'${mysql_pass}'","db_name":"'${db_name}'","mail":"'${user_email}'","user":"root","pass":"'${user_pass}'","timezone":"'${timezone}'","si":"'${si}'","mt_threads":"'${mt_threads}'","link":"'${http_type}':\/\/'${domain}${subfolder_}'\/"}'
    fi
    log "Tracker install"
    cd "${files_path}${subfolder}/" && php "${files_path}${subfolder}/index.php" "${tracker_settings}" | tee -a "${log_file}"
    si_check off
    if [[ ! -f "${check_space_folder}/binom_check_space.sh" ]]; then
        free_space_check
    fi
    bash "${check_space_folder}/binom_check_space.sh"
}

goodbye () {
    binom_version=$(grep Version "${files_path}${subfolder}/configuration/info.xml" | sed 's/<version>//g' | sed 's/<\/version>//g' | awk '{print $2}')

    echo ""
    echo ""
    echo "Thank you for using our autoinstaller."
    echo "If you made a mistake in domain name - just run this script again."
    echo ""
    echo "Binom version: ${binom_version}"
    echo ""
    echo "Access to your tracker:"
    echo "${http_type}://${domain}${subfolder}/${index_file}"
    echo "Login: root"
    echo "Password: ${user_pass}"
    {
        echo "Access to your tracker:"
        echo "${http_type}://${domain}${subfolder}/${index_file}"
        echo "Login: root"
        echo "Password: ${user_pass}"
    } > /root/.binom

    nohup sh -c 'sleep 7200 && rm /root/.binom' >>/dev/null 2>&1 &
}

get_ioncube () {
    #local url=http://downloads3.ioncube.com/loader_downloads
    local url && url=http://downloads.ioncube.com/loader_downloads
    local file && file=''

    case $(uname -m) in

        i686) file="ioncube_loaders_lin_x86_${ioncube_version}.tar.gz"
            ;;
        x86_64) file="ioncube_loaders_lin_x86-64_${ioncube_version}.tar.gz"
            ;;
        *)    exit 1
            ;;
    esac

    wget -c "${url}/${file}" -O "/tmp/$file" >> "${log_file}" 2>&1
    printf -- "/tmp/%s" "${file}"
}

ioncube_install () {
    if [[ -z $(find "${php_path}/fpm/conf.d/" -name \*ioncube.ini) ]]; then
        log "Installing ionCube.." "+"
        local php_modules_dir && php_modules_dir="$(php -r 'echo(ini_get("extension_dir"));')"
        if [[ ! -d /opt ]]; then
            mkdir /opt
        fi
        local php_modules_dir && php_modules_dir="/opt"
        local ioncube_module_name && ioncube_module_name="ioncube_loader_lin_${php_version}.so"
        local ioncube_src_path && ioncube_src_path="ioncube/${ioncube_module_name}"
        local ioncube_dst_path && ioncube_dst_path="${php_modules_dir}/ioncube/${ioncube_module_name}"
        local ioncub_tarball && ioncub_tarball="$1"
        tar \
            --extract \
            --no-same-owner \
            --no-same-permission \
            --file "${ioncub_tarball}" \
            --directory \
                "${php_modules_dir}" \
            --strip-components=0 \
                "${ioncube_src_path}" >> "${log_file}" 2>&1
        if [[ -f "$ioncube_dst_path" ]]; then
            chmod 644 "${ioncube_dst_path}"
        else
            printf -- "Error: Fail to change permissions on %S\n" "${ioncube_dst_path}"
            exit 1
        fi
        echo "; configuration for php IonCube module
; priority=00
zend_extension=${ioncube_dst_path}" > "${php_path}/mods-available/ioncube.ini"
        #old_php_support
        php5enmod ioncube >> "${log_file}" 2>&1
        phpenmod ioncube >> "${log_file}" 2>&1
    else
        log "Installing ionCube - already installed" "+"
    fi
}

check_second_install () {

    if ! [ "${nginx_fail}" == 1 ]
        then
            # check if tracker has installed
            if  [ "${config_path}" == '/etc/nginx/sites-available/binom' ] && [ -f /etc/nginx/sites-available/binom ]
                then
                    echo "
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!!!!!!!!!!!!!!!!! W A R N I N G !!!!!!!!!!!!!!!!!!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

The Binom is already installed.
Are you sure to delete tracker files?
"
                            PS3='
Please choose option: 
'
                    options=("Yes" "No")
                    select opt in "${options[@]}"
                    do
                        case $opt in
                            "Yes")
                                mysql_pass
                                rm "${config_path}"
                                rm /etc/nginx/sites-enabled/binom
                                rm -rf "${files_path}"
                                break
                                   ;;
                            "No")
                                echo "
Done!
Have a nice day!
"
                                exit 1
                                ;;
                                *) echo "Choose \"1\" or \"2\"";;
                        esac
                    done
            fi
            check_domain_exist 
    fi
}

check_domain_exist () {
    log "Check domain for exist.."
    skipped_alarm=""
    if [[ -d /etc/nginx/sites-available ]]; then
        check_domain_exist_=$(grep -r "\ ${domain};\|\ ${domain}\ " /etc/nginx/sites-available/)
        if [[ -n "${check_domain_exist_}" ]]; then 
            echo "The domain already exists, skipping: ${domain}"
            echo ""
            skipped_domains+="${domain} "
            skipped_alarm=1
        fi
    fi
}

install_domain_config () {

    log "Installing domain (${domain}).." "+"

    if ! [[ -d "${files_path}" ]]; then
        mkdir -p "${files_path}"
    fi
    
    cat <<'EOF' > "$config_path"
server {
    listen 80;
    listen [::]:80;

    root HELLO_ROOT;
    index index.html index.php;
    try_files $uri $uri/ =404;

    server_name HELLO_DOMAIN;

    access_log off;
    error_log /var/log/nginx/binom.error.log;

    # Binom url customization
    error_page 404 = /click.php?type=404;

    location ~ \.php$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        try_files $fastcgi_script_name =404;
        set $path_info $fastcgi_path_info;
        fastcgi_param PATH_INFO $path_info;
        fastcgi_index index.php;

        fastcgi_param  SCRIPT_FILENAME    $document_root$fastcgi_script_name;
        fastcgi_param  QUERY_STRING       $query_string;
        fastcgi_param  REQUEST_METHOD     $request_method;
        fastcgi_param  CONTENT_TYPE       $content_type;
        fastcgi_param  CONTENT_LENGTH     $content_length;

        fastcgi_param  SCRIPT_NAME        $fastcgi_script_name;
        fastcgi_param  REQUEST_URI        $request_uri;
        fastcgi_param  DOCUMENT_URI       $document_uri;
        fastcgi_param  DOCUMENT_ROOT      $document_root;
        fastcgi_param  SERVER_PROTOCOL    $server_protocol;
        fastcgi_param  HTTPS              $https if_not_empty;

        fastcgi_param  GATEWAY_INTERFACE  CGI/1.1;
        fastcgi_param  SERVER_SOFTWARE    nginx/$nginx_version;

        fastcgi_param  REMOTE_ADDR        $remote_addr;
        fastcgi_param  REMOTE_PORT        $remote_port;
        fastcgi_param  SERVER_ADDR        $server_addr;
        fastcgi_param  SERVER_PORT        $server_port;
        fastcgi_param  SERVER_NAME        $server_name;

        fastcgi_param  REDIRECT_STATUS    200;

        fastcgi_pass unix:/var/run/php/phpHELLO_PHP_VERSION-fpm.sock;
    }

############### SSL Settings ###############
#        
#    listen 443 ssl HELLO_HTTP2;
#    listen [::]:443 ssl HELLO_HTTP2;
#
#    HELLO_HTTP_MAX_FIELD_SIZE
#
#    keepalive_timeout 60;
#    ssl_certificate /etc/letsencrypt/live/HELLO_DOMAIN/fullchain.pem;
#    ssl_certificate_key /etc/letsencrypt/live/HELLO_DOMAIN/privkey.pem;
#    ssl_trusted_certificate /etc/letsencrypt/live/HELLO_DOMAIN/chain.pem;
#    ssl_ciphers EECDH:+AES256:-3DES:RSA+AES:RSA+3DES:!NULL:!RC4;
#    ssl_prefer_server_ciphers on;
#    ssl_protocols TLSv1 TLSv1.1 TLSv1.2;
#    
#    ssl_session_timeout 5m;
#    ssl_session_cache shared:SSL:10m;
#    
#    ssl_stapling on;
#    ssl_stapling_verify on;
#    resolver 8.8.8.8 8.8.4.4 1.1.1.1;
#
#    add_header Strict-Transport-Security "max-age=31536000";
#
############################################
     
}
EOF
    sed -i 's/'HELLO_DOMAIN'/'"${domain}"'/' "${config_path}"
    sed -i 's#'HELLO_ROOT'#'"${files_path}"'#' "${config_path}"
    sed -i 's#'HELLO_PHP_VERSION'#'"${php_version}"'#' "${config_path}"

    #Old nginx check for http/2
    nginx_http2=$(dpkg -l | grep nginx | head -n 1 | awk '{print $3}' | grep '^1.1')
    if [ -z "${nginx_http2}" ]; then
        sed -i 's/'\ HELLO_HTTP2'/''/' "${config_path}" >> "${log_file}" 2>&1
        sed -i 's/'HELLO_HTTP_MAX_FIELD_SIZE'/''/' "${config_path}" >> "${log_file}" 2>&1
    else
        sed -i 's/'\ HELLO_HTTP2'/'\ http2'/' "${config_path}" >> "${log_file}" 2>&1
        sed -i 's/'HELLO_HTTP_MAX_FIELD_SIZE'/'http2_max_field_size\ 8k\;'/' "${config_path}" >> "${log_file}" 2>&1
    fi

    #Remove IPv6 section if IPv6 not exist
    if [[ ${ipv6_status} == 0 ]]; then
        sed -i '/^.*listen \[\:\:\].*$/d' "${config_path}" >> "${log_file}" 2>&1
    fi

    #For Debian 7/8
    old_php_support

    if [ "${config_path}" == "/etc/nginx/sites-available/binom" ]; then
        if ! [[ -h /etc/nginx/sites-enabled/binom ]]; then
            ln -s "${config_path}" /etc/nginx/sites-enabled/binom
        fi
    else
        if ! [[ -h "/etc/nginx/sites-enabled/${domain}" ]]; then
            ln -s "${config_path}" "/etc/nginx/sites-enabled/${domain}"
        fi
    fi

    nginx -s reload >> "${log_file}" 2>&1
    nginx_fail=""
    http_type='http'
}

install_domain_config_ssl () {

    if [[ -n "${no_ssl}" ]]; then
        return 1
    fi

    log "Installing SSL (${domain}).."
    
    ssl_by_certbot
    if [[ -s "/etc/letsencrypt/live/${domain}/fullchain.pem" ]]; then
        rm "$config_path" >> "${log_file}" 2>&1
        cat <<'EOF' > "$config_path"
server {
    listen 80;
    listen [::]:80;
    
    root HELLO_ROOT;
    index index.html index.php;
    try_files $uri $uri/ =404;
        
    server_name HELLO_DOMAIN;

    access_log off;
    error_log /var/log/nginx/binom.error.log;

    # Binom url customization
    error_page 404 = /click.php?type=404;

    location ~ \.php$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        try_files $fastcgi_script_name =404;
        set $path_info $fastcgi_path_info;
        fastcgi_param PATH_INFO $path_info;
        fastcgi_index index.php;
            
        fastcgi_param  SCRIPT_FILENAME    $document_root$fastcgi_script_name;
        fastcgi_param  QUERY_STRING       $query_string;
        fastcgi_param  REQUEST_METHOD     $request_method;
        fastcgi_param  CONTENT_TYPE       $content_type;
        fastcgi_param  CONTENT_LENGTH     $content_length;
            
        fastcgi_param  SCRIPT_NAME        $fastcgi_script_name;
        fastcgi_param  REQUEST_URI        $request_uri;
        fastcgi_param  DOCUMENT_URI       $document_uri;
        fastcgi_param  DOCUMENT_ROOT      $document_root;
        fastcgi_param  SERVER_PROTOCOL    $server_protocol;
        fastcgi_param  HTTPS              $https if_not_empty;
            
        fastcgi_param  GATEWAY_INTERFACE  CGI/1.1;
        fastcgi_param  SERVER_SOFTWARE    nginx/$nginx_version;
            
        fastcgi_param  REMOTE_ADDR        $remote_addr;
        fastcgi_param  REMOTE_PORT        $remote_port;
        fastcgi_param  SERVER_ADDR        $server_addr;
        fastcgi_param  SERVER_PORT        $server_port;
        fastcgi_param  SERVER_NAME        $server_name;
            
        fastcgi_param  REDIRECT_STATUS    200;
            
        fastcgi_pass unix:/var/run/php/phpHELLO_PHP_VERSION-fpm.sock;
    }

############### SSL Settings ###############
        
    listen 443 ssl HELLO_HTTP2;
    listen [::]:443 ssl HELLO_HTTP2;

    HELLO_HTTP_MAX_FIELD_SIZE
     
    keepalive_timeout 60;
    ssl_certificate /etc/letsencrypt/live/HELLO_DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/HELLO_DOMAIN/privkey.pem;
    ssl_trusted_certificate /etc/letsencrypt/live/HELLO_DOMAIN/chain.pem;
    ssl_ciphers EECDH:+AES256:-3DES:RSA+AES:RSA+3DES:!NULL:!RC4;
    ssl_prefer_server_ciphers on;
    ssl_protocols TLSv1 TLSv1.1 TLSv1.2;
    
    ssl_session_timeout 5m;
    ssl_session_cache shared:SSL:10m;
    
    ssl_stapling on;
    ssl_stapling_verify on;
    resolver 8.8.8.8 8.8.4.4 1.1.1.1;

    add_header Strict-Transport-Security "max-age=31536000";

############################################


}
EOF
        sed -i 's/'HELLO_DOMAIN'/'"${domain}"'/' "$config_path" >> "${log_file}" 2>&1
        sed -i 's#'HELLO_ROOT'#'"${files_path}"'#' "${config_path}" >> "${log_file}" 2>&1
        sed -i 's#'HELLO_PHP_VERSION'#'"${php_version}"'#' "${config_path}"

        #Old nginx check for http/2
        nginx_http2=$(dpkg -l | grep nginx | head -n 1 | awk '{print $3}' | grep '^1.1')
        if [[ -z "${nginx_http2}" ]]; then
            sed -i 's/'\ HELLO_HTTP2'/''/' "${config_path}" >> "${log_file}" 2>&1
            sed -i 's/'HELLO_HTTP_MAX_FIELD_SIZE'/''/' "${config_path}" >> "${log_file}" 2>&1
        else
            sed -i 's/'\ HELLO_HTTP2'/'\ http2'/' "${config_path}" >> "${log_file}" 2>&1
            sed -i 's/'HELLO_HTTP_MAX_FIELD_SIZE'/'http2_max_field_size\ 8k\;'/' "${config_path}" >> "${log_file}" 2>&1
        fi
        #Remove IPv6 section if IPv6 not exist
        if [[ ${ipv6_status} == 0 ]]; then
          sed -i '/^.*listen \[\:\:\].*$/d' "${config_path}" >> "${log_file}" 2>&1
        fi
        old_php_support
        case "${config_path}" in
          "/etc/nginx/sites-available/binom")
            if ! [[ -h "/etc/nginx/sites-enabled/binom" ]]; then
              ln -s "${config_path}" "/etc/nginx/sites-enabled/binom" >> "${log_file}" 2>&1
            fi
            ;;
          *)
            if ! [[ -h "/etc/nginx/sites-enabled/${domain}" ]]; then
              ln -s "${config_path}" "/etc/nginx/sites-enabled/${domain}" >> "${log_file}" 2>&1
            fi
            ;;
        esac
        nginx -s reload >> "${log_file}" 2>&1
        http_type='https'
    else
        log "Can't obtain SSL certificate for your domain. Please check /var/log/letsencrypt/letsencrypt.log for detailed information or contact Binom support (support.binom.org)." "+"
    fi
}

install_default_domain () {
    log "Install default nginx config.." "+"
    local config_path=/etc/nginx/conf.d/default.conf
    cat <<'EOF' > "${config_path}"
server {
    listen 80 default_server;
    listen [::]:80;

    root HELLO_ROOT;
    index index.html index.php;
    try_files $uri $uri/ =404;

    server_name redirect-domain;

    access_log off;
    error_log /var/log/nginx/binom.error.log;

    # Binom url customization
    #error_page 404 = /click.php?type=404;

    location ~ \.php$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        try_files $fastcgi_script_name =404;
        set $path_info $fastcgi_path_info;
        fastcgi_param PATH_INFO $path_info;
        fastcgi_index index.php;

        fastcgi_param  SCRIPT_FILENAME    $document_root$fastcgi_script_name;
        fastcgi_param  QUERY_STRING       $query_string;
        fastcgi_param  REQUEST_METHOD     $request_method;
        fastcgi_param  CONTENT_TYPE       $content_type;
        fastcgi_param  CONTENT_LENGTH     $content_length;

        fastcgi_param  SCRIPT_NAME        $fastcgi_script_name;
        fastcgi_param  REQUEST_URI        $request_uri;
        fastcgi_param  DOCUMENT_URI       $document_uri;
        fastcgi_param  DOCUMENT_ROOT      $document_root;
        fastcgi_param  SERVER_PROTOCOL    $server_protocol;
        fastcgi_param  HTTPS              $https if_not_empty;

        fastcgi_param  GATEWAY_INTERFACE  CGI/1.1;
        fastcgi_param  SERVER_SOFTWARE    nginx/$nginx_version;

        fastcgi_param  REMOTE_ADDR        $remote_addr;
        fastcgi_param  REMOTE_PORT        $remote_port;
        fastcgi_param  SERVER_ADDR        $server_addr;
        fastcgi_param  SERVER_PORT        $server_port;
        fastcgi_param  SERVER_NAME        $server_name;

        fastcgi_param  REDIRECT_STATUS    200;

        fastcgi_pass unix:/var/run/php/phpHELLO_PHP_VERSION-fpm.sock;
    }
}
EOF
    sed -i 's#'HELLO_ROOT'#'"${files_path}"'#' "${config_path}" >> "${log_file}" 2>&1
    sed -i 's#'HELLO_PHP_VERSION'#'"${php_version}"'#' "${config_path}"
    #Remove IPv6 section if IPv6 not exist
    if [[ ${ipv6_status} == 0 ]]; then
      sed -i '/^.*listen \[\:\:\].*$/d' "${config_path}" >> "${log_file}" 2>&1
    fi
    nginx -s reload >> "${log_file}" 2>&1
}

old_php_support () {
    if [[ -d /etc/php5/fpm && ! -d "/etc/php/${php_version}/fpm" ]]; then
        sed -i 's#'"php/php${php_version}-fpm"'#'php5-fpm'#' "${config_path}" >> "${log_file}" 2>&1
    elif [[ -d /etc/php/5.6/fpm && ! -d /etc/php/${php_version}/fpm ]]; then
        sed -i 's#'"php/php${php_version}-fpm"'#'php/php5.6-fpm'#' "${config_path}" >> "${log_file}" 2>&1
    fi
}

permissions () {
    chmod -R 755 /var/www/binom
    chown -R www-data /var/www/binom
}

check_minimal_ram () {
    total_ram=$(free -m | sed -n 2p | awk '{print $2}')
    total_ram_recommended=1800
    if (("${total_ram}" < "${total_ram_recommended}")); then
        echo "
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!!!!!!!!!!!!!!!!! W A R N I N G !!!!!!!!!!!!!!!!!!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

Your server does not meet minimum requirements!

We do not guarantee the performance and stability
because tracker needs 2048mb RAM or more. 
(your server has only ${total_ram}mb)"
        cancel_installation
    fi
}

disable_auto_updates_ubuntu () {
    log "Disabling auto-updates.." "+"
    if [ -f /etc/apt/apt.conf.d/20auto-upgrades ]; then
        sed -i 's/1/0/' /etc/apt/apt.conf.d/20auto-upgrades
    fi
}

pass_generator () {
    symbols="0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
    lenght="$1"
    while [ "${symbol:=1}" -le "$lenght" ]
    do
        password="${password}${symbols:$((RANDOM%${#symbols})):1}"
        ((symbol+=1))
    done
    symbol=0
    echo "${password}"
}

check_nginx () {
    if [[ -z "${ignore_os}" ]]; then
        check_os
    fi
    log "NGINX check errors:"
    #nginx_check=`service nginx status 2>> ${log_file} | grep 'active (running)'`
    nginx -t >> "${log_file}" 2>&1
    nginx_check=$(tail -n 1 "${log_file}" | grep 'test failed')
    if [[ -n "${nginx_check}" ]]; then
        log "$1" "+"
        if [[ -z "${nginx_fail}" ]]; then
            nginx_fail=1
            case $2 in
                start)
                    exit 0
                    ;;
                *)
                    install_domain_config
                    ;;
            esac
        fi
    fi
}

check_fpm (){
    log "FPM check errors:"
    service php5-fpm status >> "${log_file}" 2>&1
    true>"${log_file_temp}"
    service php5-fpm status 2>> "${log_file_temp}" 1>&2
    # Debian 7 fix
    if [[ "${os_version}" == "wheezy" ]]; then
        fpm5_check=$(grep 'is running' "${log_file_temp}")
    else
        fpm5_check=$(grep 'active (running)' "${log_file_temp}")
    fi
    service php5.6-fpm status >> "${log_file}" 2>&1
    true>"${log_file_temp}"
    service php5.6-fpm status 2>> "${log_file_temp}" 1>&2
    if [[ "${os_version}" == "wheezy" ]]; then
        fpm5_6_check=$(grep 'is running' "${log_file_temp}")
    else
        fpm5_6_check=$(grep 'active (running)' "${log_file_temp}")
    fi
    service php"${php_version}"-fpm status >> "${log_file}" 2>&1
    true>"${log_file_temp}"
    service php"${php_version}"-fpm status 2>> "${log_file_temp}" 1>&2
    if [[ "${os_version}" == "wheezy" ]]; then
        fpm7_check=$(grep 'is running' "${log_file_temp}")
    else
        fpm7_check=$(grep 'active (running)' "${log_file_temp}")
    fi
    if [[ -z "${fpm5_check}" && -z "${fpm5_6_check}" && -z "${fpm7_check}" ]]; then
        echo "PHP-FPM is not loaded!"
    fi
}

check_mysql () {
    log "MySQL check errors:"
    service mysql status >> "${log_file}" 2>&1
    true>"${log_file_temp}"
    service mysql status 2>> "${log_file_temp}" 1>&2
    if [[ ${os_version} == "wheezy" ]]; then
        mysql_check=$(grep 'is running' "${log_file_temp}")
    else
        mysql_check=$(grep 'active (running)' "${log_file_temp}")
    fi
    if [[ -z ${mysql_check} ]]; then
        #Error Check
        log "MySQL is not loaded!" "+"
        echo "Please check it or tell about it here: support.binom.org"
        exit 1
    fi
}

help () {
    cat<<EOF

Usage: bash binom_install.sh [OPTION]...

Mandatory arguments to long options are mandatory for short options too.

    i, install                        - To install tracker
                --domain=onetwo.com   - To install tracker with domain onetwo.com.
                --email=admin@a.com   - To install tracker with email admin@a.com
                --timezone=+12:00     - To install tracker with timezone GMT+12
                --subfolder=name      - To install tracker to subfolder with "name"
                --version=1.12.005    - To install tracker version 1.12.005 
                                        (available: 1.9.011, 1.10.009, 1.11.002, 1.12.005, 1.13.007, 1.15.108, 1.16.009, 1.17.024)
                --db_name=name        - You can write your name of database
                --magic-checker       - Install with Magic Checker Super Filter
                --check-rkn           - Check IP with Roskomnadzor (actual for Russian traffic only)

    t, trackdomain                    - To add domain for redirects
                --domain="onetwo.com" - To install domain onetwo.com with silent mode. 
                                        You also can use some domains together: "onetwo.com twothree.com"
                --email=admin@a.com   - To setup email for your domains
                --silent=add          - To add new domains in silent mode
                --silent=delete       - To delete domains in silent mode

    l, lpdomain                       - To add external domain for landing pages
                --domain="onetwo.com" - To install domain onetwo.com with silent mode. 
                                        You also can use some domains together: "onetwo.com twothree.com"
                --email=admin@a.com   - To setup email for your domains
                --silent=add          - To add new domains in silent mode
                --silent=delete       - To delete domains in silent mode

    s, space                          - To add our additional information in monitor 
                                        (Binom v.1.9 and later)

    ssl                               - To add free SSL with Let'sEncrypt to your domains
                --domain="onetwo.com" - To install domain onetwo.com with silent mode. 
                                        You also can use some domains together: "onetwo.com twothree.com"
                --email=admin@a.com   - To setup email for your domains
                --force               - Regenerate SSL certs

    m, magicchecker                   - To install/remove MagicChecker Super Filter
    a, adspect                        - To install/remove Adspect Cloaker

    --no-ssl                          - Do not create free SSL with Let'sEncrypt
    --help                            - Display this help and exit
    --ignore-os                       - To ignore OS checking

EOF
}

check_download () {
    log "Checking file $2 ($1)" ""
    wget --spider -S "$1" >> "${log_file}" 2>&1
    check_file=$(grep "HTTP/" "${log_file}" | tail -n 1 | awk '{print $2}')
    if ! [[ ${check_file} == 200 ]]; then
        if [[ -n "$3" ]]; then
            echo "An error occurred while files downloading ($2 - $1)
Please try again later or write to our support (cp.binom.org/support)"
            exit 1
        fi
        echo 0
    else
        echo 1
    fi
}

mysql_pass () {
    log "Finding MySQL password.." "+"
    system_php=$(find /var/www/ /home/ -name system.php | tail -n 1)
    if [[ -f /root/.my.cnf ]]; then
        mysql_pass=$(grep password /root/.my.cnf | sed 's/password=//g')
    elif [[ -n "${mysql_pass}" ]]; then
        mysql_pass=$(grep 'this->password' "${system_php}" | sed 's/^[ \t]*//;s/[ \t]*$//' | sed "s/\$this->password=//g" | tr -d \' | sed 's/..$//')
    else
        check_mysql
        echo "MySQL root password is not found! Please enter it if you know or press Ctrl+C:"
        read -r mysql_pass
        while [[ -z "$(mysql -uroot -p"${mysql_pass}" -e "show databases;" 2>> "${log_file}")" ]]
        do
            echo "Password is wrong, try again:"
            read -r mysql_pass
        done
    fi
}

install_magicchecker () {
    log "Installing MagicChecker.." "+"
    {
        mkdir /usr/share/mcproxy
        # --no-check-certificate is the MagicChecker official recommendation
        wget --no-check-certificate https://clients.magicchecker.com/files/proxy/mcsproxy.zip -O /usr/share/mcproxy/mcsproxy.zip
    } >> "${log_file}" 2>&1
    if [[ -f /usr/share/mcproxy/mcsproxy.zip ]]; then
        {
            apt-get -y update
            apt-get -y install unzip 
            cd /usr/share/mcproxy/ && unzip mcsproxy.zip && rm mcsproxy.zip
        } >> "${log_file}" 2>&1
        interface=$(ip addr | awk '{print $2}' | grep "^.*:$" | grep -v "lo" | sed 's/://g' | head -n 1)
        {
            sed -i "s/eth0/${interface}/g" /usr/share/mcproxy/app.json
            bash /usr/share/mcproxy/start.sh
        } >> "${log_file}" 2>&1
    else
        log "Download error. Please check ${log_file} for detailed information or contact Binom support (support.binom.org)." "+"
        exit 1
    fi
}

check_rkn () {
    log "Checking ip (${ip_rkn}).." "+"
    {
        apt-get -y update
        apt-get -y install curl 
    } >> "${log_file}" 2>&1
    check_rkn=$(curl -m 30 --silent https://rkn.binom.org/?ip="${ip_rkn}" | grep 1)
    if [[ -n "${check_rkn}" ]]; then
        echo ""
        echo "IP address of this server ${ip_rkn} is blocked by Russia�s state communications regulator Roskomnadzor."
        echo "Do you plan to work with traffic from Russia?"
        echo ""
    PS3='
Please enter your choice: '
    options=("Yes" "No")
        select opt in "${options[@]}"
        do
            case $opt in
                "Yes")
                    echo ""
                    echo "It's very likely that traffic from Russia won't reach this server without losses"
                    echo "You can continue installation if you are OK with it, otherwise you can cancel installation and run it on another server."
                    echo "What do you want to do?"
                    cancel_installation
                    break
                    ;;
                "No")
                    echo ""
                    echo "It's fine, you can continue installation since this blocking won't affect any traffic other than Russian."
                    break
                    ;;
                *) echo "Choose \"1\" or \"2\""
                    ;;
            esac
        done
    else
        log "${ip_rkn} - OK" "+"
    fi
}

check_rescue_mode () {
    rescue_mode=$(hostname | grep -i rescue)
    if [[ -n ${rescue_mode} ]]; then
        echo "
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!!!!!!!!!!!!!!! W A R N I N G !!!!!!!!!!!!!!!!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

It looks like your server loaded in rescue mode!
Please reboot it and continue installation.

"
        exit 1
    fi
}

check_root_folder () {
    max_total_space_folder=$(df | grep -Ev '(tmpfs|Filesystem)' | sort -nk 2 | tail -n 1 | awk '{printf $6}')
    if ! [[ "${max_total_space_folder}" == "/" ]]; then
        echo "
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!!!!!!!!!!!!!! W A R N I N G !!!!!!!!!!!!!!!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

It looks like partitions setup isn't standard!

Please contact https://support.binom.org for further information or 
continue the installation if you are OK with this disk partiioning:
"
        df -h
        cancel_installation
    fi
}

cancel_installation () {
    echo ""
    PS3='
Please enter your choice: '
    options=("Continue installation" "Cancel installation.")
    select opt in "${options[@]}"
    do
        case $opt in
            "Continue installation")
                break
                ;;
            "Cancel installation.")
                exit 0
                ;;
        esac
    done
}

tracker_version () {
    if [[ -z "${tracker_version}" ]]; then
        tracker_version=Latest
    else
        case "${tracker_version}" in
            1.17.024) php_version=7.4 ;;
            1.16.009) php_version=7.4 ;;
            1.15.108) php_version=7.4 ;;
            1.13.007) php_version=7.3 ;;
            1.12.005) php_version=7.3 ;;
            1.11.002) php_version=5.6 ;;
            1.10.009) php_version=5.6 ;;
            1.9.011) php_version=5.6 ;;
            *) echo "Incorrect version"; exit 1 ;;
        esac
    fi
    if [[ $(check_download "https://s3.eu-central-1.amazonaws.com/data.binom.org/installer/Install_Binom_${tracker_version}.tar.gz" "binom archive" "exit") == 1 ]]; then
        tracker_download="https://s3.eu-central-1.amazonaws.com/data.binom.org/installer/Install_Binom_${tracker_version}.tar.gz"
    fi
}

ssl_by_certbot () {
    # Too old legacy support
    if [[ -f /root/certbot-auto || ${os_version} == jessie ]]; then
        if [ -f /root/certbot-auto ]; then
            rm /root/certbot-auto >> "${log_file}" 2>&1
        fi
        wget -O /root/certbot-auto https://raw.githubusercontent.com/certbot/certbot/v1.17.0/certbot-auto >> "${log_file}" 2>&1
        #temporary fix for certbot
        sed -i 's/virtualenv --no-site-packages/virtualenv --no-download --no-site-packages/' /root/certbot-auto

        chmod a+x /root/certbot-auto
        if [[ ! -f "/etc/cron.d/lets-encrypt-renew" ]]; then
            echo '0 3 * * *     root        /root/certbot-auto renew --renew-hook "nginx -s reload" >> /var/log/letsencrypt/renew.log ' > /etc/cron.d/lets-encrypt-renew
        fi
        service cron restart >> "${log_file}" 2>&1

        /root/certbot-auto certonly -n --webroot --agree-tos --email "${user_email}" -d "${domain}" -w "${files_path}" >> "${log_file}" 2>&1
    else
        # skip if old apt certbot package exist
        if ! check_installed python-certbot-nginx; then
            # install new snap package
            {
                apt-get -y install snapd
                snap install core
                snap refresh core
                snap install --classic certbot
            } >> "${log_file}" 2>&1
            check_exit
            if ! [[ -s /usr/bin/certbot ]]; then
                ln -s /snap/bin/certbot /usr/bin/certbot >> "${log_file}" 2>&1
            fi
        fi
        # Changing main certbot timer file for legacy apt packages
        if [[ -f /lib/systemd/system/certbot.service ]]; then
            if ! grep -q "renew-hook" /lib/systemd/system/certbot.service; then
                sed -i 's#renew#renew --renew-hook "nginx -s reload"#g' /lib/systemd/system/certbot.service >> "${log_file}" 2>&1
                systemctl daemon-reload >> "${log_file}" 2>&1
            fi
        fi
        # Drop main certbot cron file for old users
        if [[ -f /etc/cron.d/certbot ]]; then
            rm /etc/cron.d/certbot >> "${log_file}" 2>&1
        fi
        # Remove old certs if we want to create new fresh
        # due to old certbot/certbot-auto errors
        if [[ -n "${force_option}" ]]; then
            log "--force opiton, remove old cert"
            if [[ -d "/etc/letsencrypt/live" ]]; then
                rm -rf /etc/letsencrypt/live/"${domain}"* >> "${log_file}" 2>&1
            fi
            if [[ -d "/etc/letsencrypt/archive" ]]; then
                rm -rf /etc/letsencrypt/archive/"${domain}"* >> "${log_file}" 2>&1
            fi
            if [[ -d "/etc/letsencrypt/renewal" ]]; then
                rm -rf /etc/letsencrypt/renewal/"${domain}"*.conf >> "${log_file}" 2>&1
            fi
        fi
        certbot certonly -n --webroot --agree-tos --email "${user_email}" -d "${domain}" -w "${files_path}" >> "${log_file}" 2>&1
        if [[ ! -f "/etc/cron.d/lets-encrypt-renew" ]]; then
            echo '0 3 * * *     root        certbot renew --renew-hook "nginx -s reload" >> /var/log/letsencrypt/renew.log' > /etc/cron.d/lets-encrypt-renew
        fi
        if grep -q certbot-auto /etc/crontab; then
            sed -i 's#/root/certbot-auto#certbot#g' /etc/crontab >> "${log_file}" 2>&1
        fi
        service cron restart >> "${log_file}" 2>&1
    fi
}

si_check () {
    # For <3GB RAM slow servers, local install
    case $1 in
        on)
            if (("$total_ram" < "2850")); then 
                case ${tracker_version} in
                    Latest|1.13.007|1.15.108|1.16.009|1.17.024)
                        si=1
                        if ! grep -q localhost /etc/nginx/sites-available/binom; then
                            sed -i '/^[ \t]*server_name/s/'"${domain}"'/'"${domain}"\ localhost'/1' /etc/nginx/sites-available/binom >> "${log_file}" 2>&1
                            service nginx reload >> "${log_file}" 2>&1
                        fi
                        if ! grep -q "${domain}" /etc/hosts; then
                            echo "127.0.0.1 ${domain}" >> /etc/hosts
                        fi
                        ;;
                    *)
                        si=0
                        ;;
                esac
            else
                si=0
            fi
            ;;
        off)
            sed -i '/^[ \t]*server_name/s/'"${domain}"\ localhost'/'"${domain}"'/1' /etc/nginx/sites-available/binom >> "${log_file}" 2>&1
            service nginx reload >> "${log_file}" 2>&1
            sed -i '/'"${domain}"'/d' /etc/hosts >> "${log_file}" 2>&1
            ;;
    esac
}

delete_custom_domains () {
    declare -a DOMAINS="( $dmains )"
    for domain in "${DOMAINS[@]}"
    do 
        if [[ -f "/etc/nginx/sites-available/${domain}" ]]; then
            rm "/etc/nginx/sites-available/${domain}" >> "${log_file}" 2>&1
            rm "/etc/nginx/sites-enabled/${domain}" >> "${log_file}" 2>&1
            if [[ -e "/etc/letsencrypt/live/${domain}/cert.pem" ]]; then
                if [[ -f /root/certbot-auto ]]; then
                    /root/certbot-auto -n revoke --cert-name "${domain}" >> "${log_file}" 2>&1
                    /root//root/certbot-auto -n delete --cert-name "${domain}" >> "${log_file}" 2>&1
                else 
                    certbot -n revoke --cert-name "${domain}" >> "${log_file}" 2>&1
            certbot -n delete --cert-name "${domain}" >> "${log_file}" 2>&1
                fi
            fi
            echo "${domain} has been removed!"
        else
            check_main_domain=$(grep '^[[:blank:]]*server_name' /etc/nginx/sites-available/binom | head -n 1 | sed 's/server_name//g' | sed 's/^[ \t]*//;s/\;//;s/[ \t]*$//g')
            if [[ "${domain}" == "${check_main_domain}" ]]; then
                echo ""
                log "This domain (${domain}) is main, so you can't delete it." "+"
                echo ""
            else
                sed -i '/^[ \t]*server_name/s/ '"${domain}"'//1' /etc/nginx/sites-available/binom >> "${log_file}" 2>&1
                log "${domain} has been removed!" "+"
            fi
        fi
    done
}

add_redirect_domains () {
    declare -a DOMAINS="( $dmains )"
    for domain in "${DOMAINS[@]}"
    do
        log "${domain}.." ""
        config_path=/etc/nginx/sites-available/${domain}
        check_domain_exist
        if [[ -z "${skipped_alarm}" ]]; then
            install_domain_config
            domain_validation
            install_domain_config_ssl
            check_nginx "Can't obtain SSL certificate, domain will be configured without SSL.."
            echo ""
            echo "Done! Now you can use your new domain: ${http_type}://${domain}"
            echo ""
        fi
    done
    if [[ -n ${skipped_domains} ]]; then
        echo "Warning! Some domains were skipped."
        echo "Skipped domains: ${skipped_domains}"
        echo ""
    fi
}

add_lp_domains () {
    declare -a DOMAINS="( $dmains )"
    for domain in "${DOMAINS[@]}"
    do 
        log "${domain}.." ""
        files_path="/var/www/${domain}"
        config_path="/etc/nginx/sites-available/${domain}"

        check_domain_exist
        if [[ -z "${skipped_alarm}" ]]; then
            install_domain_config
            {
                # For root
                sed -i '/root/s#'/binom\;'#'/"${domain}"\;'#1' "${config_path}"
                # For error.log
                sed -i '/error_log/s#'/binom.error'#'/"${domain}".error'#' "${config_path}"
                # Remove binom customization
                sed -i '/Binom url customization/d' "${config_path}"
                sed -i '/type=404/d' "${config_path}"
                nginx -s reload
            } >> "${log_file}" 2>&1

            if [[ ! -f ${files_path}/index.html ]]; then
                wget "https://s3.eu-central-1.amazonaws.com/data.binom.org/config/html/template.html" -O "${files_path}/index.html" >> "${log_file}" 2>&1
                sed -i 's/domain/'"$domain"'/' "${files_path}/index.html" >> "${log_file}" 2>&1
            fi
            if [[ ! -f ${files_path}/robots.txt ]]; then
                echo 'User-agent: *' >> "${files_path}/robots.txt"
                echo 'Disallow: /' >> "${files_path}/robots.txt"
            fi

            domain_validation
            install_domain_config_ssl
            {
                # For root
                sed -i '/root/s#'/binom\;'#'/"${domain}"\;'#1' "${config_path}"
                # For error.log
                sed -i '/error_log/s#'/binom.error'#'/"${domain}".error'#' "${config_path}"
                # Remove binom customization
                sed -i '/Binom url customization/d' "${config_path}"
                sed -i '/type=404/d' "${config_path}"
                nginx -s reload
            } >> "${log_file}" 2>&1

            chown -R www-data "/var/www/${domain}"

            check_nginx "Can't obtain SSL certificate, domain will be configured without SSL.."
            {
                # For root
                sed -i '/root/s#'/binom\;'#'/"${domain}"\;'#1' "${config_path}"
                # For error.log
                sed -i '/error_log/s#'/binom.error'#'/"${domain}".error'#' "${config_path}"
                # Remove binom customization
                sed -i '/Binom url customization/d' "${config_path}"
                sed -i '/type=404/d' "${config_path}"
                nginx -s reload
            } >> "${log_file}" 2>&1

            echo "Done! Now you can use your new domain: ${http_type}://${domain}"
            echo "and drop your files into this folder: ${files_path}"
            echo ""
        fi
    done
    if [[ -n ${skipped_domains} ]]; then
        echo "Warning! Some domains were skipped."
        echo "Skipped domains: ${skipped_domains}"
        echo ""
    fi
}

domain_validation () {
    if [[ -n ${no_ssl_option} ]]; then
      no_ssl=1
      return 1
    fi

    log "Check domain exist"
    # Calculate nginx reload time
    if [[ -z "${nginx_reload_time}" ]]; then
        time_start=$(date +%s)
        nginx -t >> "${log_file}" 2>&1
        time_stop=$(date +%s)
        nginx_reload_time=$((time_stop - time_start))
        nginx_reload_time=$((nginx_reload_time + 1))
        log "nginx_reload_time: ${nginx_reload_time}"
    fi
    # Sleep after previous nginx reload
    sleep "${nginx_reload_time}"
    domain_validation_file=$(pass_generator 32)
    echo "1" > "${files_path}/${domain_validation_file}"
    chmod 755 "${files_path}/${domain_validation_file}" >> "${log_file}" 2>&1
    n=3
    for (( i=0; i<="${n}"; i++ )); do
        domain_validation=$(curl --max-time 10 "http://${domain}/${domain_validation_file}" 2>> "${log_file}")
    if [[ "${domain_validation}" = 1 ]]; then
            no_ssl=""
            i="${n}"
        elif [[ "${i}" = "${n}" ]]; then
            no_ssl=1
            echo "Can't validate domain name, please make sure that the DNS A/AAAA record(s) for that domain
contain(s) the right IP address or contact Binom support (support.binom.org)"
        else
            log "Retrying.." "+"
            sleep "${nginx_reload_time}"
        fi
    done
    rm "${files_path}/${domain_validation_file}" >> "${log_file}" 2>&1
}

check_exit () {
    exit_code=$?
    if ! [[ ${exit_code} == 0 ]]; then
        log "Something went wrong. Please check ${log_file} for detailed information or contact Binom support (support.binom.org)." "+"
        exit 1
    fi
}

php_version_detect () {
    if [[ -z "${php_version}" ]]; then
        if [[ -f /etc/nginx/sites-available/binom ]]; then
            nginx_php=$(grep '^[[:blank:]]*fastcgi_pass' /etc/nginx/sites-available/binom)
        else
            nginx_php=$(grep '^[[:blank:]]*fastcgi_pass' /etc/nginx/sites-available/*  2>>"${log_file}" | tail -n 1)
        fi
        if [[ -n "${nginx_php}" ]]; then
            case "${nginx_php}" in
                *php5-fpm*) php_version="5" ;;
                *php5.6-fpm*) php_version="5.6" ;;
                *php7.1-fpm*) php_version="7.1" ;;
                *php7.2-fpm*) php_version="7.2" ;;
                *php7.3-fpm*) php_version="7.3" ;;
                *php7.4-fpm*) php_version="7.4" ;;
            esac
        else
            php_version="7.4"
        fi
    fi
}

clean_resolve () {
    # Check systemd-resolve
    if [[ -f "/run/systemd/resolve/stub-resolv.conf" ]]; then
        if ! service systemd-resolved status | grep -q disabled; then
            {
                systemctl disable --now systemd-resolved.service
                service systemd-resolved stop
                rm /etc/resolv.conf
                touch /etc/resolv.conf
            } >> "${log_file}" 2>&1
            # Non empty file for sed
            echo "" > /etc/resolv.conf
        fi
    fi
    if [[ -f "/etc/resolv.conf" ]]; then
        if ! grep -q "8.8.8.8" /etc/resolv.conf; then
            sed -i '1inameserver 8.8.8.8\nnameserver 1.1.1.1' /etc/resolv.conf
        fi
    fi
}

check_arm () {
    if uname -m | grep -qi arm; then
        echo "

    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    !!!!!!!!! W A R N I N G !!!!!!!!!!!
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

    1Click can not be used with ARM CPU

"
        exit 1
    fi
}

check_ipv6 () {
    if [[ -z "$(ip -6 addr)" ]]; then
        ipv6_status=0
    fi
}

check_openvz () {
    if [ "$(systemd-detect-virt)" == "openvz" ]; then
        echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!!!!!!!!!!!!!!! W A R N I N G !!!!!!!!!!!!!!!!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
It seems that your server is running under OpenVZ virtualization.
We recommend to use server with KVM virtualization instead.
You can get these servers here: https://docs.binom.org/faq.php#6.
Please note that tracker's performance and stability is not guaranteed if you decide to use OpenVZ.
Please contact https://support.binom.org for further information or 
continue the installation if you take the risk:"
        cancel_installation
    fi
}

post_install () {
    case ${tracker_version} in
        Latest|1.13.007|1.15.108|1.16.009|1.17.024)
            cd "${files_path}${subfolder}/" || exit 1
            index_file=$(php "${files_path}${subfolder}/index.php" 2>/dev/null)
            #index_file_real="$(grep 'this->index' "${files_path}${subfolder}/configuration/custom_url.php" | sed 's/^[ \t]*//;s/[ \t]*$//' | sed "s/\$this->index=//g;s/\"//g;s/\;//;s/\\r//g").php"
            ;;
        *)
            index_file="index.php"
            ;;
    esac
}

install_grpc () {
    if [[ ! -f "/etc/php/${php_version}/mods-available/grpc.ini" ]]; then
        log "Installing grpc.." "+"
        {
            apt-get -y install autoconf zlib1g-dev 2>> "${log_file}" 1>&2
            curl -sS https://getcomposer.org/installer -o /tmp/installer
            php /tmp/installer --install-dir=/usr/local/bin --filename=composer
            pecl install grpc 
        } 2>> "${log_file}" 1>&2
        cat <<EOF > "/etc/php/${php_version}/mods-available/grpc.ini"
; priority=00
extension=grpc.so
EOF
        phpenmod grpc 2>> "${log_file}" 1>&2
    else
        log "Installing grpc - already installed" "+"
    fi
}

echo "ClientAliveInterval 60" >> /etc/ssh/sshd_config
service sshd restart

#Check for root
if [ "$EUID" != "0" ]; then 
    echo "Error! Please run as root"
    exit 1
fi

check_rescue_mode
check_arm
check_ipv6

if [[ ! -d /var/log/binom ]]; then
    mkdir /var/log/binom
fi

for arg in "$@" ; do
    case "$arg" in
        --domain=*|-d=*)
            # For tracker install
            domain="${arg#*=}"
            # For custom domains
            dmains="${arg#*=}"
            ;;
        --silent=*)
            silent="${arg#*=}"
            ;;
        --email=*|-e=*)
            user_email="${arg#*=}"
            ;;
        --php5|--php5.6)
            php_version=5.6
            ;;
        --no-ssl|--nossl)
            no_ssl_option=1
            ;;
        --force)
            force_option=1
            ;;
        --ignore-os)
            ignore_os=1
            ;;
        --version|-v)
            echo "${version}"
            ;;
        --help)
            help
            exit
            ;;
        *)
            ;;
    esac
done

case $1 in

    trackdomain|track|t)

        log "Start $1 option" "+"

        php_version_detect
        clean_resolve

        if [[ -z ${ignore_os} ]]; then
            check_os
        fi
        check_nginx "You have some problems with Nginx. Please check ${log_file} for detailed information or contact Binom support (support.binom.org)" "start"

        if [[ -z ${silent} ]]; then
            echo ""
            echo "What do you want?"
            PS3='
Please choose option: '
            options=("Add new domain(s) for redirects" "Delete old domain(s) for redirects")
            select opt in "${options[@]}"
            do
                case $opt in
                    "Add new domain(s) for redirects")
                        dmains=''
                        read_variable dmains "Enter name for new domain (if you need two or more domains, enter them space-separated):"
                        dmains="${dmains,,}"
                        if [[ -z "${no_ssl_option}" ]]; then
                            read_variable user_email "Enter your mail for SSL notification: " 
                            echo ""
                        fi
                        files_path=$(grep root /etc/nginx/sites-available/binom 2>> "${log_file}" | head -1 | sed 's/root//g' | sed 's/^[ \t]*//;s/[ \t]*$//' | sed 's/.$//')
                        if [[ -z "${files_path}" ]]; then
                            log "Oops! Where is your tracker?" "+"
                            exit 0
                        fi
                        add_redirect_domains
                        break
                        ;;
                    "Delete old domain(s) for redirects")
                        log "Deleting old domain(s) for redirects" ""
                        read_variable dmains "Please enter domain(s) name that you want to delete:"
                        domain="${domain,,}"
                        echo ""
                        echo "Are you sure?"
                        PS3='
Please choose option: '
                        options=("Yes" "No")
                        select opt in "${options[@]}"
                        do
                            case $opt in
                                "Yes")
                                    delete_custom_domains
                                    nginx -s reload >> "${log_file}" 2>&1
                                    break
                                    ;;
                                "No")
                                    exit 0
                                    ;;
                                *) echo "Choose \"1\" or \"2\""
                                ;;
                            esac
                        done
                        break
                        ;;
                esac
            done
        elif [[ -n ${dmains} ]]; then
            if [[ -z ${no_ssl_option} ]] && [[ -z ${user_email} ]]; then
                echo ""
                echo "Please add --email="foo@bar.com" if you want to use --silent=add or --silent=delete options."
                echo ""
                exit 1
            else
                case $silent in
                    add)
                        files_path=$(grep root /etc/nginx/sites-available/binom 2>> "${log_file}" | head -1 | sed 's/root//g' | sed 's/^[ \t]*//;s/[ \t]*$//' | sed 's/.$//')
                        if [[ -z ${files_path} ]]; then
                            log "Oops! Where is your tracker?" "+"
                            exit 0
                        fi
                        add_redirect_domains
                        ;;
                    delete)
                        delete_custom_domains
                        ;;
                esac
            fi
        else
            echo ""
            echo "Please add --domain=\"foo.bar\" or --domain=\"foo.com bar.org\" if you want to use --silent=add or --silent=delete options."
            echo ""
            exit 1
        fi
        ;;

    space_check|space|s)

        log "Start $1 option" "+"

        check_space_folder=$(pwd)
        free_space_check
        bash "${check_space_folder}/binom_check_space.sh"
        echo ""
        echo "Done!"
        echo "Space_check script is ready."
        ;;

    lpdomain|add|+|l)

        log "Start $1 option" "+"

        php_version_detect
        clean_resolve

        php_path="/etc/php/${php_version}"
        fpm_config="https://s3.eu-central-1.amazonaws.com/data.binom.org/config/php/www.conf"

        if [[ -z ${ignore_os} ]]; then
            check_os
        fi
        if ! [ -f /etc/nginx/nginx.conf ]; then
             echo "
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!!!!!!!! W A R N I N G !!!!!!!!!!!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

Nginx is not found. 
And now it will be installed :)

"
            declare depends=(
                nginx 
                php7.4-fpm
                php7.4-mbstring 
                php7.4-xml 
                php7.4-zip 
                php7.4-curl 
                curl )

            get_nginx
            get_ppa

            check_and_install
            get_config_nginx
            get_config_php
            
            nginx -s reload >> "${log_file}" 2>&1
        fi
        check_nginx "You have some problems with Nginx. Please, contact binom support if you dont know how to fix it." "start"

        if [[ -z ${silent} ]]; then
            echo ""
            echo "What do you want?"
            echo ""
            PS3='
Please choose option: '
            options=("Add new domain(s) for landing pages" "Delete old domain(s) for landing pages")
            select opt in "${options[@]}"
            do
                case $opt in
                    "Add new domain(s) for landing pages")
                        dmains=''
                        read_variable dmains "Enter name for new domain (if you need two or more domains, enter them space-separated): " 
                        dmains="${dmains,,}"

                        if [[ -z "${no_ssl_option}" ]]; then
                            read_variable user_email "Enter your mail for SSL notification: " 
                            echo ""
                        fi
                        add_lp_domains
                        break
                        ;;
                    "Delete old domain(s) for landing pages")
                        log "Deleting old domain(s) for landing pages" ""
                        read_variable dmains "Please enter domain(s) that you want to delete:"
                        dmains="${dmains,,}"
                        echo ""
                        echo "Are you sure?"
                        echo "" 
                        PS3='
Please choise option:'
                        options=("Yes" "No")
                        select opt in "${options[@]}"
                        do
                            case $opt in
                                "Yes")
                                    delete_custom_domains
                                    nginx -s reload >> "${log_file}" 2>&1
                                    break
                                    ;;
                                "No")
                                    exit 0
                                    ;;
                                *) echo "Choose \"1\" or \"2\""
                                    ;;
                            esac
                        done
                        break
                        ;;
                esac
            done
        elif [[ -n ${dmains} ]]; then
            if [[ -z ${no_ssl_option} ]] && [[ -z ${user_email} ]]; then
                echo ""
                echo "Please add --email="foo@bar.com" if you want to use --silent=add or --silent=delete options."
                echo ""
                exit 1
            else
                case $silent in
                    add)
                        add_lp_domains
                        ;;
                    delete)
                        delete_custom_domains
                        ;;
                esac
            fi
        else
            echo ""
            echo "Please add --domain=\"foo.bar\" or --domain=\"foo.com bar.org\" if you want to use --silent=add or --silent=delete options."
            echo ""
        fi
        ;;

    ssl)
        log "Start $1 option" "+"

        php_version_detect
        clean_resolve

        # We assume that the domain already exists
        http_type="http"

        if [[ -z ${ignore_os} ]]; then
            check_os
        fi
        check_nginx "You have some problems with Nginx. Please, contact binom support if you dont know how to fix it." "start"
        if [[ -z ${dmains} ]]; then
            read_variable dmains "Please enter domain(s) that you want to add SSL:"
        fi
        if [[ -z ${user_email} ]]; then
            read_variable user_email "Enter your mail for SSL notification: "
            echo ""
        fi

        echo ""
        declare -a DOMAINS="( $dmains )"
        for domain in "${DOMAINS[@]}"
        do
            log "SSL to ${domain}.." "+"
            if [[ -f "/etc/nginx/sites-enabled/${domain}" ]]; then
                files_path=$(grep root "/etc/nginx/sites-enabled/${domain}" 2>> "${log_file}" | head -1 | sed 's/root//;s/\;//;s/^[ \t]*//;s/[ \t]*$//')
                check_binom=$(grep error_log "/etc/nginx/sites-enabled/${domain}" | grep 'binom.error')
                config_path=/etc/nginx/sites-available/${domain}
                domain_validation
                install_domain_config_ssl
                if [[ -z ${check_binom} ]]; then
                    {
                        # For root
                        sed -i 's#'/binom\;'#'/"${domain}"\;'#' "${config_path}"
                        # For error.log
                        sed -i 's#'/binom\.'#'/"${domain}"\.'#' "${config_path}"
                        nginx -s reload
                    } >> "${log_file}" 2>&1
                fi
                check_nginx "Can't obtain SSL certificate, domain (${domain}) will be configured without SSL.."
            else
                # For binom file and aliases
                files_path=$(grep root /etc/nginx/sites-available/binom 2>> ${log_file} | head -1 | sed 's/root//g' | sed 's/^[ \t]*//;s/[ \t]*$//' | sed 's/;//')
                if [[ ! -d "${files_path}" ]]; then
                    log "Oops! Where is your tracker?" "+"
                    exit 1
                fi
                    # Check old legacy alias mode
                    check_empty=$(grep '^[[:blank:]]*server_name' /etc/nginx/sites-available/binom | head -n 1 | sed '/^[ \t]*server_name/s/ '"${domain}"'//1;s/^[ \t]*//;s/server_name//;s/\;//;s/[ \t]*$//g')
                    if [[ -z ${check_empty} ]]; then
                          config_path=/etc/nginx/sites-available/binom
                    else
                        # Remove alias and use additional file
                    sed -i '/^[ \t]*server_name/s/ '"${domain}"'//1' /etc/nginx/sites-available/binom >> "${log_file}" 2>&1
                        config_path="/etc/nginx/sites-available/${domain}"
                    fi
                domain_validation
                install_domain_config_ssl

                check_nginx "Can't obtain SSL certificate, domain (${domain}) will be configured without SSL.."
            fi
            if [ "${http_type}" = "http" ]; then
                echo "Today without SSL, sorry:  ${http_type}://${domain} 
                "
            else
                echo "SSL is ready:  ${http_type}://${domain} 
                "
            fi
        done
        ;;

    install|inst|i)

        log "Starting $1 option.." "+"

        check_openvz

        for arg in "$@" ; do
            case "$arg" in
                --timezone=*|-t=*)
                    timezone="${arg#*=}"
                    ;;
                --db_name=*)
                    db_name="${arg#*=}"
                    ;;
                --subfolder=*|--folder=*)
                    subfolder="/${arg#*=}"
                    ;;
                --version=*|-v=*)
                    tracker_version="${arg#*=}"
                    ;;
                --debug)
                    domain=$(ip addr | sed -En 's/127.0.0.1//;s/.*inet (addr:)?(([0-9]*\.){3}[0-9]*).*/\2/p' | head -n 1)
                    user_email=debug@debug.debug
                    user_pass=debug
                    timezone=+3:00
                    ;;
                --magic-checker|--magicchecker)
                    magicchecker=1
                    ;;
                --check-rkn|--rkn)
                    ip_rkn=$(ip addr | sed -En 's/127.0.0.1//;s/.*inet (addr:)?(([0-9]*\.){3}[0-9]*).*/\2/p' | head -n 1)
                    check_rkn=1
                    ;;
                *)
                    ;;
            esac
        done

        if [[ -z ${ignore_os} ]]; then
            check_os
        fi
        check_minimal_ram
        check_root_folder

        if [[ -n ${check_rkn} ]]; then
            check_rkn
        fi

        declare check_installed=(nginx httpd apache2 percona-server-server-5.7 mysql-server mariadb-server ispmanager sp-serverpilot-agent vesta)
        for package in "${check_installed[@]}"
        do
            if check_installed "${package}"; then
                alarm=1
                alarm_soft+="${package}"
                alarm_soft+=" "
            fi
        done

        files_path="/var/www/binom"

        if [[ "${alarm}" = "1" ]]; then
            echo "
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!! W A R N I N G !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

Auto-installer has detected third-party software on your server:

${alarm_soft}

If you choose to proceed with installation, it can break your current settings. 
The installation process should be performed only on clean server. 
You can skip this warning if you already have Binom installed by auto-installer.
For more information, go to: https://cp.binom.org/page/support
Continue?
"
            PS3='
Please enter your choice: '
            options=("Yes" "No")
            select opt in "${options[@]}"
            do
                case $opt in
                    "Yes")
                        break
                        ;;
                    "No")
                        exit
                        ;;
                    *) echo "Choose \"1\" or \"2\"";;
                esac
            done
        fi

        check_space_folder=$(pwd)
        config_path="/etc/nginx/sites-available/binom"

        if [[ -z ${domain} ]]; then
            read_variable domain "Enter domain name for tracker:"
        fi
        domain="${domain,,}"

        tracker_version
        tracker_setup

        echo "" 
        echo "Now you can make yourself comfortable, maybe even pour a cup of tea and, slowly sipping it, wait for auto installer to finish its job in 15-25 minutes"
        echo ""

        log "Updating package's info.." "+"
        apt-get -y update >> "${log_file}" 2>&1
        check_exit

        log "Updating packages.." "+"
        apt-get -y autoremove >> "${log_file}" 2>&1
        check_exit

        apt-mark hold grub-pc libpq-dev >> "${log_file}" 2>&1
        export DEBIAN_FRONTEND=noninteractive
        yes | apt-get -q -y dist-upgrade >> "${log_file}" 2>&1
        check_exit
        apt-mark unhold grub-pc libpq-dev >> "${log_file}" 2>&1

        log "Installing additional packages.." "+"
        {
            apt-get install -y ca-certificates
            apt-get install -y gpg-agent
            apt-get install -y lsb-release
            apt-get install -y curl
            apt-get install -y gnupg
            apt-get install -y gnupg1
            apt-get install -y gnupg2
            apt-get install -y g++
            apt-get install -y make
        } >> "${log_file}" 2>&1
        # not check_exit and separate installs because many version of OS

        get_nginx
        get_percona

        if [[ -z ${php_version} ]]; then
            php_version="7.4"
        fi
        fpm_config="https://s3.eu-central-1.amazonaws.com/data.binom.org/config/php/www.conf"

        declare depends=(
            nginx
            curl
            whois
            "php${php_version}-curl"
            "php${php_version}-fpm"
            "php${php_version}-mbstring" 
            "php${php_version}-mysql"
            "php${php_version}-xml"
            "php${php_version}-zip"
            "php${php_version}-ssh2"
            "php${php_version}-dev"
            "php-pear"
            cron)

        get_ppa
        check_and_install
        update-alternatives --set php "/usr/bin/php${php_version}" >> "${log_file}" 2>&1

        disable_auto_updates_ubuntu

        php_path="/etc/php/${php_version}"
        mysql_path="/etc/mysql/conf.d"

        ioncube_install "$(get_ioncube)"
        install_grpc
        get_config_nginx
        get_config_php                
        get_config_mysql

        service "php${php_version}-fpm" restart >> "${log_file}" 2>&1

        clean_resolve

        install_domain_config
        domain_validation
        install_domain_config_ssl

        check_nginx "Can't obtain SSL certificate, domain will be configured without SSL.."

        install_default_domain

        download_and_unpack

        if [[ ${magicchecker} = 1 ]]; then
            install_magicchecker
        fi

        check_fpm
        check_mysql

        post_install
        goodbye
        permissions
        exit 0
        ;;
    m|magicchecker)
        if ss -ntulp | grep -q ':8082' || [[ -d /usr/share/mcproxy ]]; then
            echo ""
            echo "Magic Filter is already installed. "
            echo "Remove it?"
            PS3='
Please choose option: '
            options=("Yes" "No, wait..")
            select opt in "${options[@]}"
            do
                case $opt in
                    "Yes")
                        if [[ -f /usr/share/mcproxy/stop.sh ]]; then
                            bash /usr/share/mcproxy/stop.sh >> "${log_file}" 2>&1
                            rm -rf /usr/share/mcproxy >> "${log_file}" 2>&1
                            echo "Done!"
                        else
                            echo "stop.sh is not found!"
                        fi
                        exit 0
                        ;;
                    "No, wait..")
                        exit 0
                        ;;
                esac
            done
        else
            echo ""
            echo "Install the MagicChecker?"
            PS3='
Please choose option: '
            options=("Yes" "No")
            select opt in "${options[@]}"
            do
                case $opt in
                "Yes")
                    install_magicchecker
                    echo "Done!"
                    exit 0
                    ;;
                "No")
                    exit 0
                    ;;
                esac
            done
        fi
        ;;
    a|adspect)
        if [[ -f /usr/local/bin/adspectd ]]; then
            echo ""
            echo "Adspect is already installed. "
            echo "Remove it?"
            PS3='
Please choose option: '
            options=("Yes" "No")
            select opt in "${options[@]}"
            do
                case $opt in
                    "Yes")
                        log "Removing Adspect.." "+"
                        {
                            service adspectd stop
                            rm -rf /lib/systemd/system/adspectd.service /usr/local/bin/adspectd
                            systemctl daemon-reload 
                        } >> "${log_file}" 2>&1
                        echo "Done!"
                        exit 0
                        ;;
                    "No")
                        exit 0
                        ;;
                esac
            done
        else
            echo ""
            echo "Install the Adspect?"
            PS3='
Please choose option: '
            options=("Yes" "No")
            select opt in "${options[@]}"
            do
                case $opt in
                    "Yes")
                        log "Installing Adspect.." "+"
                        if [[ -f /lib/systemd/system/adspect.service ]]; then
                            echo "Oops! Adspect already installed!"
                        else
                            {
                                wget https://s3.eu-central-1.amazonaws.com/data.binom.org/3rd-party/adspect/adspectd -O /usr/local/bin/adspectd
                                chmod 755 /usr/local/bin/adspectd
                                mkdir -p /var/lib/adspect
                                touch /var/lib/adspect/adspectd.state
                                touch /var/log/adspectd.log
                                apt-get -y update
                                apt-get -y install whois
                            } >> "${log_file}" 2>&1
                            if [[ -f /usr/local/bin/adspectd ]]; then
                                cat <<'EOF' > /lib/systemd/system/adspectd.service
# This file is part of Adspect Sieve anti-fraud software.
# Copyright (C) 2019-2021 by Adspect.  All rights reserved.

[Unit]
Description=Adspect Sieve anti-fraud software
Documentation=https://adspect.readthedocs.io/en/latest/
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/adspectd --listen=127.0.0.1:8003 --s=/var/lib/adspect/adspectd.state
ExecReload=/bin/sh -c "/bin/kill -s HUP $(/bin/pidof adspectd)"
ExecStop=/bin/sh -c "/bin/kill -s TERM $(/bin/pidof adspectd)"
StandardOutput=/var/log/adspectd.log
StandardError=/var/log/adspectd.log
Restart=always

[Install]
WantedBy=multiser.target
EOF
                                {
                                    systemctl daemon-reload
                                    service adspectd start
                                } >> "${log_file}" 2>&1
                                echo "Done!"
                                exit 0
                            else
                                log "Download error. Please check ${log_file} for detailed information or contact Binom support (support.binom.org)." "+"
                                exit 1
                            fi
                        fi
                        ;;
                    "No")
                        exit 0
                        ;;
                esac
            done
        fi
        ;;
    *)
        help
        ;;
esac
sed -i "/ClientAliveInterval 60/ d" /etc/ssh/sshd_config
service sshd restart
exit 0
