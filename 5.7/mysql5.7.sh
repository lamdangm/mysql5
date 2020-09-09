#!/bin/sh
# Variables for installing
SOURCE=`pwd`
MDATA="/data/mysql/MYSQL57"
INSDIR="mysql57"
Password_MySQL="admin"
PORT="3306"

mkdir -p $SOURCE
mkdir -p $MDATA
mkdir $MDATA/data
mkdir $MDATA/log
touch $MDATA/log/mysql_slow.log
touch $MDATA/log/server_log.log

#yum groupinstall "Development Tools" -y
yum -y install gcc-c++ openssl openssl-devel ncurses-devel cmake git wget bzip2 unzip bison

adduser -d /nonexistent -s /sbin/nologin mysql
############################

cd $SOURCE
wget https://dev.mysql.com/get/Downloads/MySQL-5.7/mysql-boost-5.7.26.tar.gz
tar xfz mysql-boost-5.7.26.tar.gz
# Building MySQL with Boost
cd mysql-5.7.26
#create folder my_boost and compile MySQL
mkdir my_boost
cmake . -DDOWNLOAD_BOOST=1 -DCMAKE_INSTALL_PREFIX:PATH=/usr/local/$INSDIR -DMYSQL_DATADIR=$MDATA/data \
 -DWITH_EXTRA_CHARSETS=sjis,ujis,euckr -DWITH_BOOST=./my_boost \
 -DMYSQL_TCP_PORT=$PORT \
 -DMYSQL_UNIX_ADDR=/tmp/mysqld57.sock
make
make install

rm /etc/my.cnf -rf
echo "
[mysqld]
socket  = /tmp/mysqld57.sock
port    = 3306
bind-address = 0.0.0.0
basedir = /usr/local/mysql57
datadir = /data/mysql/MYSQL57/data
expire-logs-days=2
pid-file=/usr/local/mysql57/mysql57.pid
#log_slow_queries=/data/mysql/MYSQL57/log/mysql_slow.log
long_query_time=3
default_authentication_plugin=mysql_native_password
log-bin=/data/mysql/MYSQL57/log/mysql-bin
server-id=3
log-error = /data/mysql/MYSQL57/log/mysql57.err
slow_query_log = 1
slow-query_log_file=/data/mysql/MYSQL57/log/m57-slave-slow.log

innodb_log_group_home_dir = /data/mysql/MYSQL57/log

relay_log = /data/mysql/MYSQL57/log/mysql-relay-bin
master-info-file = /data/mysql/MYSQL57/log/master.info
relay_log_info_file = /data/mysql/MYSQL57/log/relay-log.info
relay_log_purge=1

log_slave_updates = true
" > /usr/local/$INSDIR/my.cnf

touch /usr/local/mysql57/mysql57.pid
cd /usr/local
chown -R mysql.mysql $INSDIR -R

/usr/local/$INSDIR/bin/mysqld --initialize --user=mysql --basedir=/usr/local/$INSDIR --datadir=$MDATA/data \
> $MDATA/log/mysqld_initialize.log 2>&1

tmp_PassMysql=`awk '/temporary password/ {print $11}' $MDATA/log/mysqld_initialize.log`

#change permission
touch /data/mysql/MYSQL57/log/mysql57.err
cd /usr/local
chown -R mysql.mysql $INSDIR -R
chown -R mysql.mysql $MDATA

# start up service
/bin/cp -rf /usr/local/$INSDIR/support-files/mysql.server /etc/init.d/mysqld57
chmod +x /etc/init.d/mysqld57
chkconfig --add mysqld57
chkconfig mysqld57 on
service mysqld57 start

rm -rf /usr/bin/mysql
ln -s /usr/local/$INSDIR/bin/mysql /usr/bin/mysql

#Change password root of mysql
mysql --user="root" --password="$tmp_PassMysql"  --connect-expired-password -S /tmp/mysqld57.sock --execute="ALTER USER 'root'@'localhost' IDENTIFIED BY '$Password_MySQL';"
mysql --user="root" --password="$Password_MySQL" --connect-expired-password -S /tmp/mysqld57.sock --execute="create user 'root'@'%' IDENTIFIED BY '$Password_MySQL'; grant all privileges on *.* to 'root'@'%'; flush privileges;"
mysql --user="root" --password="$Password_MySQL" --connect-expired-password -S /tmp/mysqld57.sock --execute="SET GLOBAL slow_query_log = 'ON';SET GLOBAL long_query_time = 3;SET GLOBAL slow_query_log_file ='$MDATA/log/mysql_slow.log';"
