#!/bin/sh

if [ "$DEBUG" != "" ]; then
	set -x 
fi

APACHECONFWALLA=/etc/apache2/conf.d/wallabag.conf
WALLABAGROOT=/web/wallabag
WALLABAGPATH=/web/wallabag/web
WALLABAGSQLITE=/web/wallabag/data/db/wallabag.sqlite
WALLABAGDBINIT=$WALLABAGROOT/data/db/db.initialized
WALLABAGDBCONF=$WALLABAGROOT/app/config/parameters.yml
MAXTRIES=20


if [ "$SUBURI" == "" ]; then
	echo "[i] Using default URI: /"
	SUBURI="/"
fi
echo "[i] Serving URI: $SUBURI"


if [ -f $APACHECONFWALLA ]; then
	echo "[i] SUBURI already configured!"
else
	echo "[i] Configuring URI: $SUBURI"
	cat <<EOF > $APACHECONFWALLA
<Directory $WALLABAGPATH>
    Options FollowSymLinks
    AllowOverride All
    Require all granted
</Directory>

Alias $SUBURI "$WALLABAGPATH/"
LoadModule rewrite_module modules/mod_rewrite.so
EOF
fi

cd $WALLABAGROOT

if [ "$DEBUG" != "" ]; then
	set -x 
fi


wait4mysql () {
echo "[i] Waiting for database to setup..."

for i in $(seq 1 1 $MAXTRIES)
do
	echo "[i] Trying to connect to database: try $i..."
	if [ "$DB_ENV_MYSQL_PASSWORD" = "" ]; then
		mysql -B --connect-timeout=1 -h db -u $DB_ENV_MYSQL_USER -e "SELECT VERSION();" $DB_ENV_MYSQL_DATABASE 
	else
		mysql -B --connect-timeout=1 -h db -u $DB_ENV_MYSQL_USER -p$DB_ENV_MYSQL_PASSWORD -e "SELECT VERSION();" $DB_ENV_MYSQL_DATABASE 
	fi

	if [ "$?" = "0" ]; then
		echo "[i] Successfully connected to database!"
		break
	else
		if [ "$i" = "$MAXTRIES" ]; then
			echo "[!] You need to have container for database. Take a look at docker-compose.yml file!"
			exit 0
		else
			sleep 5
		fi
	fi
done
}

wait4psql () {
echo "[i] Waiting for database to setup..."

export PGPASSWORD=$DB_ENV_POSTGRES_PASSWORD
for i in $(seq 1 1 $MAXTRIES)
do
	echo "[i] Trying to connect to database: try $i..."
	psql -h db -U $DB_ENV_POSTGRES_USER -d $DB_ENV_POSTGRES_DB -w -c 'SELECT version();'
	if [ "$?" = "0" ]; then
		echo "[i] Successfully connected to database!"
		break
	else
		if [ "$i" = "$MAXTRIES" ]; then
			echo "[!] You need to have container for database. Take a look at docker-compose.yml file!"
			exit 0
		else
			sleep 5
		fi
	fi
done
}

FOUND_DB=0
if [ "$DB_ENV_MYSQL_USER" != "" ]; then
	echo "[i] Found MySQL setup"
	cat << EOF > $WALLABAGDBCONF
# This file is auto-generated during the docker init
parameters:
    database_driver: pdo_mysql
    database_host: db
    database_port: ~
    database_name: $DB_ENV_MYSQL_DATABASE
    database_user: $DB_ENV_MYSQL_USER
    database_password: $DB_ENV_MYSQL_PASSWORD
    database_path: ~
    database_table_prefix: wallabag_
    mailer_transport: smtp
    mailer_host: $WALLABAG_SMTPHOST
    mailer_user: $WALLABAG_SMTPUSER
    mailer_password: $WALLABAG_SMTPPASSWORD
    locale: en
    secret: $WALLABAG_SECRET
    twofactor_auth: true
    twofactor_sender: $WALLABAG_SMTPFROM
    fosuser_confirmation: true
    from_email: $WALLABAG_SMTPFROM
    fosuser_registration: true
    rss_limit: 50
    rabbitmq_host: localhost
    rabbitmq_port: 5672
    rabbitmq_user: guest
    rabbitmq_password: guest
    redis_host: localhost
    redis_port: 6379
EOF
	FOUND_DB=1
	wait4mysql
fi

if [ "$DB_ENV_POSTGRES_USER" != "" ]; then
	echo "[i] Found PostgreSQL setup"
	cat << EOF > $WALLABAGDBCONF
# This file is auto-generated during the docker init
parameters:
    database_driver: pdo_pgsql
    database_host: db
    database_port: ~
    database_name: $DB_ENV_POSTGRES_DB
    database_user: $DB_ENV_POSTGRES_USER
    database_password: $DB_ENV_POSTGRES_PASSWORD
    database_path: ~
    database_table_prefix: wallabag_
    mailer_transport: smtp
    mailer_host: $WALLABAG_SMTPHOST
    mailer_user: $WALLABAG_SMTPUSER
    mailer_password: $WALLABAG_SMTPPASSWORD
    locale: en
    secret: $WALLABAG_SECRET
    twofactor_auth: true
    twofactor_sender: $WALLABAG_SMTPFROM
    fosuser_confirmation: true
    from_email: $WALLABAG_SMTPFROM
    fosuser_registration: true
    rss_limit: 50
    rabbitmq_host: localhost
    rabbitmq_port: 5672
    rabbitmq_user: guest
    rabbitmq_password: guest
    redis_host: localhost
    redis_port: 6379
EOF
	FOUND_DB=1
	wait4psql
fi

if [ "$FOUND_DB" = "0" ]; then
	echo "[i] Container not linked with DB. Using SQLite."
	cat << EOF > $WALLABAGDBCONF
# This file is auto-generated during the docker init
parameters:
    database_driver: pdo_sqlite
    database_host: 127.0.0.1
    database_port: ~
    database_name: symfony
    database_user: root
    database_password: ~
    database_path: '%kernel.root_dir%/../data/db/wallabag.sqlite'
    database_table_prefix: wallabag_
    mailer_transport: smtp
    mailer_host: $WALLABAG_SMTPHOST
    mailer_user: $WALLABAG_SMTPUSER
    mailer_password: $WALLABAG_SMTPPASSWORD
    locale: en
    secret: $WALLABAG_SECRET
    twofactor_auth: true
    twofactor_sender: $WALLABAG_SMTPFROM
    fosuser_confirmation: true
    from_email: $WALLABAG_SMTPFROM
    fosuser_registration: true
    rss_limit: 50
    rabbitmq_host: localhost
    rabbitmq_port: 5672
    rabbitmq_user: guest
    rabbitmq_password: guest
    redis_host: localhost
    redis_port: 6379
EOF
fi


if [ -e $WALLABAGDBINIT ]; then
	echo "[i] Database exists, not creating"
else
	echo "[i] Database does not exists, creating..."
	sleep 5 # timing issue, configuration is not written for some reason
	# php bin/console wallabag:install --reset --env=$SYMFONY_ENV -n
	su apache -s /bin/sh -c 'php bin/console wallabag:install -n'
	touch $WALLABAGDBINIT
	#echo "[i] Fixing permissions"
	#chown -R apache.apache data var vendor config bin web
fi

