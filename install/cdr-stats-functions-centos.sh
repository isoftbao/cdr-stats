#!/bin/bash
#
# CDR-Stats License
# http://www.cdr-stats.org
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this file,
# You can obtain one at http://mozilla.org/MPL/2.0/.
#
# Copyright (C) 2011-2015 Star2Billing S.L.
#
# The Initial Developer of the Original Code is
# Arezqui Belaid <info@star2billing.com>
#

# Set branch to install develop / default: master
if [ -z "${BRANCH}" ]; then
    BRANCH='master'
fi

#Install mode can me either CLONE or DOWNLOAD
INSTALL_MODE='CLONE'
INSTALL_DIR='/usr/share/cdrstats'
CONFIG_DIR='/usr/share/cdrstats/cdr_stats'
WELCOME_DIR='/var/www/cdr-stats'
DATABASENAME='cdrstats_db'
CDRPUSHER_DBNAME="cdr-pusher"
DB_USERSALT=`</dev/urandom tr -dc 0-9| (head -c $1 > /dev/null 2>&1 || head -c 5)`
# DB_USERNAME="cdr_stats_$DB_USERSALT"
DB_USERNAME="cdr_stats"
# DB_PASSWORD=`</dev/urandom tr -dc A-Za-z0-9| (head -c $1 > /dev/null 2>&1 || head -c 20)`
DB_PASSWORD='isoftbao.com'
DB_HOSTNAME='localhost'
DB_PORT='5432'
CDRSTATS_USER='cdr_stats'
CELERYD_USER="celery"
CELERYD_GROUP="celery"
CDRSTATS_ENV="cdr-stats"
HTTP_PORT="8008"
DATETIME=$(date +"%Y%m%d%H%M%S")
KERNELARCH=$(uname -m)
SCRIPT_NOTICE="This install script is only intended to run on CentOS 6.X"

#Django bug https://code.djangoproject.com/ticket/16017
export LANG="en_US.UTF-8"

#一、Function to install Frontend
func_install_frontend(){

    echo ""
    echo "We will now install CDR-Stats..."
    echo ""

    #1、Function to install Dependencies
    func_install_dependencies

    #2、Install Redis
    func_install_redis

    # Fuction to create the virtual env
    # Disabled: as we are using conda
    #3、Create and enable virtualenv
    # func_setup_virtualenv

    
    #4、Function to backup the data from the previous installation
    func_backup_prev_install

    #5、Function to install the code source
    func_install_source

    #6、Fuction to create the virtual env; Setup Conda & Env
    func_setup_conda

    #7、Function to prepare settings_local.py ; Prepare Settings
    func_prepare_settings

    #8、Fuction to create  PostgreSQL Database
    func_create_pgsql_database

    #9、Install Django cdr-stats
    func_django_cdrstats_install

    #10、Install Nginx / Supervisor
    func_nginx_supervisor

    #11、Configure Logs files and logrotate
    func_prepare_logger
}

# Identify Linux Distribution
func_identify_os() {
    if [ -f /etc/redhat-release ] ; then
        DIST='CENTOS'
        if [ "$(awk '{print $3}' /etc/redhat-release)" != "6.2" ] && [ "$(awk '{print $3}' /etc/redhat-release)" != "6.3" ] && [ "$(awk '{print $3}' /etc/redhat-release)" != "6.4" ] && [ "$(awk '{print $3}' /etc/redhat-release)" != "6.5" && [ "$(awk '{print $3}' /etc/redhat-release)" != "6.10" ]; then
            echo $SCRIPT_NOTICE
            exit 255
        fi
    else
        echo $SCRIPT_NOTICE
        #exit 1
    fi
}


#1、Function to install Dependencies
func_install_dependencies(){

    #python setup tools
    echo "Install Dependencies and python modules..."
    yum -y groupinstall "Development Tools"
    yum -y install git sudo cmake
    yum -y install python-setuptools python-tools python-devel mercurial memcached
    yum -y install mlocate vim git wget
    yum -y install policycoreutils-python

    # install Node & npm
    yum -y --enablerepo=epel install npm

    #Install, configure and start nginx
    yum -y install --enablerepo=epel nginx
    chkconfig --levels 235 nginx on
    service nginx start

    #Install & Start PostgreSQL 95
    # CentOs
    rpm -ivh https://download.postgresql.org/pub/repos/yum/9.5/redhat/rhel-6-x86_64/pgdg-centos95-9.5-3.noarch.rpm
    #Redhad
    rpm -ivh https://download.postgresql.org/pub/repos/yum/9.5/redhat/rhel-6-x86_64/pgdg-redhat95-9.5-3.noarch.rpm
    yum -y install postgresql95-server postgresql95-devel
    chkconfig --levels 235 postgresql-9.5 on
    service postgresql-9.5 initdb
    ln -s /usr/pgsql-9.5/bin/pg_config /usr/bin
    ln -s /var/lib/pgsql/9.5/data /var/lib/pgsql
    ln -s /var/lib/pgsql/9.5/backups /var/lib/pgsql
    sed -i "s/ident/md5/g" /var/lib/pgsql/data/pg_hba.conf
    sed -i "s/ident/md5/g" /var/lib/pgsql/9.5/data/pg_hba.conf
    service postgresql-9.5 restart
    if which paxctl >/dev/null; then
            echo "Deactivating memory protection on nodejs and python ( prevent segfault )"
            paxctl -cm /usr/bin/nodejs
            paxctl -cm /usr/bin/node
            paxctl -cm /usr/bin/python2.7
    fi
    echo ""
    echo "easy_install -U setuptools pip distribute"
    easy_install -U setuptools pip distribute

    # install Bower
    npm config set strict-ssl false
    npm install -g bower
    ##node npm install Error: CERT_UNTRUSTED
    ##ssl验证问题，使用下面的命令取消ssl验证即可解决
    npm config set strict-ssl false

    #Create CDRStats User cdr_stats
    echo "Create CDRStats User/Group : $CDRSTATS_USER"
    groupadd -r -f $CDRSTATS_USER
    useradd -r -c "$CDRSTATS_USER" -s /bin/bash -g $CDRSTATS_USER $CDRSTATS_USER
    # useradd $CDRSTATS_USER --user-group --system --no-create-home
}
#2、Install Redis
func_install_redis() {
    echo "Install Redis-server ..."
    yum -y --enablerepo=epel install redis
    chkconfig --add redis
    chkconfig --level 2345 redis on
    /etc/init.d/redis start
}

# Fuction to create the virtual env
# Disabled: as we are using conda
#3、Create and enable virtualenv
func_setup_virtualenv() {
    echo "This will install virtualenv & virtualenvwrapper"
    echo "and create a new virtualenv : $CDRSTATS_ENV"

    pip install virtualenv
    pip install virtualenvwrapper

    #Prepare settings for installation
    # SCRIPT_VIRTUALENVWRAPPER="/usr/bin/virtualenvwrapper.sh"
    SCRIPT_VIRTUALENVWRAPPER="/opt/miniconda/bin/virtualenvwrapper.sh"
    

    # Enable virtualenvwrapper
    chk=`grep "virtualenvwrapper" ~/.bashrc|wc -l`
    if [ $chk -lt 1 ] ; then
        echo "Set Virtualenvwrapper into bash"
        echo "export WORKON_HOME=/usr/share/virtualenvs" >> ~/.bashrc
        echo "source $SCRIPT_VIRTUALENVWRAPPER" >> ~/.bashrc
    fi

    # Setup virtualenv
    export WORKON_HOME=/usr/share/virtualenvs
    source $SCRIPT_VIRTUALENVWRAPPER

    #mkvirtualenv cdr-stats
    mkvirtualenv $CDRSTATS_ENV
    workon $CDRSTATS_ENV

    echo "Virtualenv $CDRSTATS_ENV created and activated"
}


#4、Function to backup the data from the previous installation
func_backup_prev_install(){

    if [ -d "$INSTALL_DIR" ]; then
        echo ""
        echo "We detected an existing installation of CDR-Stats"
        echo "if you continue the existing installation will be removed!"
        echo ""
        echo "Press Enter to continue or CTRL-C to exit"
        read TEMP

        mkdir /tmp/old-cdr-stats_$DATETIME
        mv $INSTALL_DIR /tmp/old-cdr-stats_$DATETIME
        echo "Files from $INSTALL_DIR has been moved to /tmp/old-cdr-stats_$DATETIME"

        if [ `sudo -u postgres psql -qAt --list | egrep '^$DATABASENAME\|' | wc -l` -eq 1 ]; then
            echo "Run backup with postgresql..."
            sudo -u postgres pg_dump $DATABASENAME > /tmp/old-cdr-stats_$DATETIME.pgsqldump.sql
            echo "PostgreSQL Dump of database $DATABASENAME added in /tmp/old-cdr-stats_$DATETIME.pgsqldump.sql"
            echo "Press Enter to continue"
            read TEMP
        fi
        if [ `sudo -u postgres psql -qAt --list | egrep '^$CDRPUSHER_DBNAME\|' | wc -l` -eq 1 ]; then
            echo "Run backup with postgresql..."
            sudo -u postgres pg_dump $CDRPUSHER_DBNAME > /tmp/old-cdr-pusher_$DATETIME.pgsqldump.sql
            echo "PostgreSQL Dump of database $CDRPUSHER_DBNAME added in /tmp/old-cdr-pusher_$DATETIME.pgsqldump.sql"
            echo "Press Enter to continue"
            read TEMP
        fi
    fi
}

#5、Function to install the code source
func_install_source(){

    #get CDR-Stats
    echo "Install CDR-Stats..."
    cd /usr/src/
    rm -rf cdr-stats
    mkdir -p /var/log/cdr-stats

    # https://github.com/isoftbao/cdr-stats.git
    git clone -b $BRANCH git://github.com/isoftbao/cdr-stats.git
    cd cdr-stats

    #Install Develop / Master
    if echo $BRANCH | grep -i "^develop" > /dev/null ; then
        git checkout -b develop --track origin/develop
    fi

    # Copy files
    cp -r /usr/src/cdr-stats/cdr_stats $INSTALL_DIR
}

#6、Fuction to create the virtual env; Setup Conda & Env
func_setup_conda() {
    echo ""
    echo "Setup conda"
    echo ""
    if [ $KERNELARCH = "x86_64" ]; then
        wget --no-check-certificate http://repo.continuum.io/miniconda/Miniconda-latest-Linux-x86_64.sh -O Miniconda.sh
    else
        wget --no-check-certificate http://repo.continuum.io/miniconda/Miniconda-latest-Linux-x86.sh -O Miniconda.sh
    fi
    bash Miniconda.sh -b -p /opt/miniconda
    #this may not work if the user decided to install miniconda in diff directory
    export PATH="/opt/miniconda/bin:$PATH"

    conda info
    conda update -y conda
    # conda create -y -n $CDRSTATS_ENV python
    # not sure we need to use $CDRSTATS_ENV as the env refer by /opt/miniconda/envs/cdr-stats
    conda create -p /opt/miniconda/envs/cdr-stats python --yes
    # source /opt/miniconda/bin/activate  /opt/miniconda/envs/cdr-stats
    source activate /opt/miniconda/envs/cdr-stats
    # 'source deactivate' is deprecated. Use 'conda deactivate'.
    # conda activate  /opt/miniconda/envs/cdr-stats

    #Install Pandas with Conda
    conda install -y pandas
    conda install -y pip

    #Check what we installed in env
    conda list -p /opt/miniconda/envs/cdr-stats

    #Install Pip Dependencies
    func_install_pip_deps

    #Check what we installed in env (after pip)
    conda list -p /opt/miniconda/envs/cdr-stats
}

#Function to install Python dependencies
func_install_pip_deps(){

    echo "Install Pip Dependencies"
    echo "========================"

    pip install pytz

    echo "Install basic requirements..."
    for line in $(cat /usr/src/cdr-stats/requirements/basic.txt | grep -v '^#' | grep -v '^$')
    do
        echo "pip install $line"
        pip install $line
    done
    echo "Install Django requirements..."
    for line in $(cat /usr/src/cdr-stats/requirements/django.txt | grep -v '^#' | grep -v '^$')
    do
        echo "pip install $line --allow-all-external --allow-unverified django-admin-tools"
        pip install $line  django-admin-tools
    done
    

    #Check Python dependencies
    func_check_dependencies

    echo "**********"
    echo "PIP Freeze"
    echo "**********"
    pip freeze
}

# Checking Python dependencies
func_check_dependencies() {
    echo ""
    echo "Checking Python dependencies..."
    echo ""

    #Check Django
    grep_pip=`pip freeze| grep Django`
    if echo $grep_pip | grep -i "Django" > /dev/null ; then
        echo "OK : Django installed..."
    else
        echo "Error : Django not installed..."
        exit 1
    fi

    #Check celery
    grep_pip=`pip freeze| grep celery`
    if echo $grep_pip | grep -i "celery" > /dev/null ; then
        echo "OK : celery installed..."
    else
        echo "Error : celery not installed..."
        exit 1
    fi

    #Check django-postgres
    grep_pip=`pip freeze| grep django-postgres`
    if echo $grep_pip | grep -i "django-postgres" > /dev/null ; then
        echo "OK : django-postgres installed..."
    else
        echo "Error : django-postgres not installed..."
        exit 1
    fi

    echo ""
    echo "Python dependencies successfully installed!"
    echo ""
}

#7、Function to prepare settings_local.py ; Prepare Settings
func_prepare_settings(){
    #Copy settings_local.py into cdr-stats dir
    cp /usr/src/cdr-stats/install/conf/settings_local.py $CONFIG_DIR

    #Update Secret Key
    echo "Update Secret Key..."
    RANDPASSW=`</dev/urandom tr -dc A-Za-z0-9| (head -c $1 > /dev/null 2>&1 || head -c 50)`
    sed -i "s/^SECRET_KEY.*/SECRET_KEY = \'$RANDPASSW\'/g"  $CONFIG_DIR/settings.py
    echo ""

    #Disable Debug
    sed -i "s/DEBUG = True/DEBUG = False/g"  $CONFIG_DIR/settings_local.py
    sed -i "s/TEMPLATE_DEBUG = DEBUG/TEMPLATE_DEBUG = False/g"  $CONFIG_DIR/settings_local.py

    #Setup settings_local.py for POSTGRESQL
    sed -i "s/DATABASENAME/$DATABASENAME/"  $CONFIG_DIR/settings_local.py
    sed -i "s/DB_USERNAME/$DB_USERNAME/" $CONFIG_DIR/settings_local.py
    sed -i "s/DB_PASSWORD/$DB_PASSWORD/" $CONFIG_DIR/settings_local.py
    sed -i "s/DB_HOSTNAME/$DB_HOSTNAME/" $CONFIG_DIR/settings_local.py
    sed -i "s/DB_PORT/$DB_PORT/" $CONFIG_DIR/settings_local.py

    # settings for CDRPUSHER_DBNAME
    sed -i "s/CDRPUSHER_DBNAME/$CDRPUSHER_DBNAME/"  $CONFIG_DIR/settings_local.py

    #Setup Timezone
    #Get TZ
    . /etc/sysconfig/clock
    echo ""
    echo "We will now add port $HTTP_PORT  and port 80 to your Firewall"
    echo "Press Enter to continue or CTRL-C to exit"
    read TEMP

    #Set Timezone in settings_local.py
    sed -i "s@Europe/Madrid@$ZONE@g" $CONFIG_DIR/settings_local.py

    #Fix Iptables
    #Add http port
    iptables -I INPUT 2 -p tcp -m state --state NEW -m tcp --dport $HTTP_PORT -j ACCEPT
    iptables -I INPUT 3 -p tcp -m state --state NEW -m tcp --dport 80 -j ACCEPT

    service iptables save

    #Selinux to allow apache to access this directory
    chcon -Rv --type=httpd_sys_content_t /usr/share/virtualenvs/cdr-stats/
    chcon -Rv --type=httpd_sys_content_t $INSTALL_DIR/usermedia
    semanage port -a -t http_port_t -p tcp $HTTP_PORT
    #Allowing Apache to access Redis port
    semanage port -a -t http_port_t -p tcp 6379

    IFCONFIG=`which ifconfig 2>/dev/null||echo /sbin/ifconfig`
    IPADDR=`$IFCONFIG eth0|gawk '/inet addr/{print $2}'|gawk -F: '{print $2}'`
    if [ -z "$IPADDR" ]; then
        #the following work on Docker container
        # ip addr | grep 'state UP' -A2 | tail -n1 | awk '{print $2}' | cut -f1  -d'/'
        IPADDR=`ip -4 -o addr show eth0 | cut -d ' ' -f 7 | cut -d '/' -f 1`
        if [ -z "$IPADDR" ]; then
            clear
            echo "we have not detected your IP address automatically!"
            echo "Please enter your IP address manually:"
            read IPADDR
            echo ""
        fi
    fi
    echo "The local IP-Address used for installation is $IPADDR"

    #Update Authorize local IP
    sed -i "s/SERVER_IP_PORT/$IPADDR:$HTTP_PORT/g" $CONFIG_DIR/settings_local.py
    sed -i "s/#'SERVER_IP',/'$IPADDR',/g" $CONFIG_DIR/settings_local.py
    sed -i "s/SERVER_IP/$IPADDR/g" $CONFIG_DIR/settings_local.py
}

#8、Fuction to create  PostgreSQL Database
func_create_pgsql_database(){

    # Create the Database
    echo "We will remove existing Database"
    echo "Press Enter to continue"
    read TEMP
    echo "sudo -u postgres dropdb $DATABASENAME"
    sudo -u postgres dropdb $DATABASENAME
    echo "sudo -u postgres dropdb $CDRPUSHER_DBNAME"
    sudo -u postgres dropdb $CDRPUSHER_DBNAME
    # echo "Remove Existing Database if exists..."
    #if [ `sudo -u postgres psql -qAt --list | egrep $DATABASENAME | wc -l` -eq 1 ]; then
    #     echo "sudo -u postgres dropdb $DATABASENAME"
    #     sudo -u postgres dropdb $DATABASENAME
    # fi
    echo "Create CDR-Stats database..."
    echo "sudo -u postgres createdb $DATABASENAME"
    sudo -u postgres createdb $DATABASENAME

    #CREATE ROLE / USER
    echo "Create Postgresql user $DB_USERNAME"
    #echo "sudo -u postgres createuser --no-createdb --no-createrole --no-superuser $DB_USERNAME"
    #sudo -u postgres createuser --no-createdb --no-createrole --no-superuser $DB_USERNAME
    echo "sudo -u postgres psql --command=\"create user $DB_USERNAME with password 'XXXXXXXXXXXX';\""
    sudo -u postgres psql --command="CREATE USER $DB_USERNAME with password '$DB_PASSWORD';"

    #Create CDR-Pusher Database (we don't touch this DB if it exists)
    echo "Create CDR-Pusher database..."
    echo "sudo -u postgres createdb $CDRPUSHER_DBNAME"
    sudo -u postgres createdb $CDRPUSHER_DBNAME

    echo "Grant all privileges to user..."
    sudo -u postgres psql --command="GRANT ALL PRIVILEGES on database \"$DATABASENAME\" to \"$DB_USERNAME\";"
    sudo -u postgres psql --command="GRANT ALL PRIVILEGES on database \"$CDRPUSHER_DBNAME\" to \"$DB_USERNAME\";"
}

#9、Install Django cdr-stats
func_django_cdrstats_install(){
    cd $INSTALL_DIR/
    python manage.py syncdb --noinput
    python manage.py makemigrations
    python manage.py migrate

    clear
    echo ""
    echo "Create a super admin user..."
    python manage.py createsuperuser

    echo "Install Bower deps"
    python manage.py bower_install -- --allow-root

    echo "Collects the static files"
    python manage.py collectstatic --noinput

    #Load Countries Dialcode
    python manage.py load_country_dialcode

    #Load default gateways & billing data
    python manage.py loaddata voip_gateway/fixtures/voip_gateway.json
    python manage.py loaddata voip_gateway/fixtures/voip_provider.json
    python manage.py load_sample_voip_billing
}

#10、Install Nginx / Supervisor
func_nginx_supervisor(){
    #Leave virtualenv
    # source /opt/miniconda/bin/deactivate
    # 'source deactivate' is deprecated. Use 'conda deactivate'.
    source deactivate
    # conda deactivate

    #Configure and Start supervisor
    #Install Supervisor
    pip install supervisor

    cp /usr/src/cdr-stats/install/supervisor/centos/supervisord /etc/init.d/supervisord
    chmod +x /etc/init.d/supervisord
    chkconfig --levels 235 supervisord on
    cp /usr/src/cdr-stats/install/supervisor/centos/supervisord.conf /etc/supervisord.conf
    mkdir -p /etc/supervisor/conf.d
    cp /usr/src/cdr-stats/install/supervisor/gunicorn_cdrstats.conf /etc/supervisor/conf.d/
    mkdir /var/log/supervisor/

    /etc/init.d/supervisord stop
    sleep 2
    /etc/init.d/supervisord start
}

#11、Configure Logs files and logrotate
func_prepare_logger() {
    touch /var/log/cdr-stats/cdr-stats.log
    touch /var/log/cdr-stats/cdr-stats-db.log
    chown -R $CDRSTATS_USER:$CDRSTATS_USER /var/log/cdr-stats

    echo "Install Logrotate..."
    # First delete to avoid error when running the script several times.
    rm /etc/logrotate.d/cdr_stats
    touch /etc/logrotate.d/cdr_stats
    echo '
/var/log/cdr-stats/*.log {
        daily
        rotate 10
        size = 50M
        missingok
        compress
    }
'  > /etc/logrotate.d/cdr_stats

    logrotate /etc/logrotate.d/cdr_stats
}

#二、Function install the landing page
func_install_landing_page() {
    #mkdir -p /var/www/cdr-stats
    mkdir -p $WELCOME_DIR
    # Copy files
    cp -r /usr/src/cdr-stats/install/landing-page/* $WELCOME_DIR
    echo ""
    echo "Add Nginx configuration for Welcome page..."
    cp -rf /usr/src/cdr-stats/install/nginx/global /etc/nginx/
    cp /usr/src/cdr-stats/install/nginx/sites-available/cdr_stats.conf /etc/nginx/conf.d/
    rm /etc/nginx/conf.d/default.conf

    cp -rf /usr/src/cdr-stats/install/nginx/global /etc/nginx/

    #Restart Nginx
    service nginx restart

    #Update Welcome page IP
    sed -i "s/LOCALHOST/$IPADDR:$HTTP_PORT/g" $WELCOME_DIR/index.html
}

#三、Function to install backend
func_install_backend() {
    echo ""
    echo "This will install CDR-Stats Backend, Celery & Redis on your server"
    echo "Press Enter to continue or CTRL-C to exit"
    read TEMP

    #Create directory for pid file
    mkdir -p /var/run/celery

    #Install Celery & redis-server
    func_install_redis

    echo "Install Celery via supervisor..."
    func_celery_supervisor
}

#CELERY SUPERVISOR
func_celery_supervisor(){
    #Leave virtualenv
    # source /opt/miniconda/bin/deactivate
    # 'source deactivate' is deprecated. Use 'conda deactivate'.
    # conda deactivate
    source deactivate

    #Configure and Start supervisor
    #Install Supervisor
    pip install supervisor

    cp /usr/src/cdr-stats/install/supervisor/centos/supervisord /etc/init.d/supervisor
    chmod +x /etc/init.d/supervisor
    chkconfig --levels 235 supervisor on
    cp /usr/src/cdr-stats/install/supervisor/centos/supervisord.conf /etc/supervisord.conf
    mkdir -p /etc/supervisor/conf.d
    cp /usr/src/cdr-stats/install/supervisor/celery_cdrstats.conf /etc/supervisor/conf.d/
    mkdir /var/log/supervisor/
    /etc/init.d/supervisor stop
    sleep 2
    /etc/init.d/supervisor start
}

