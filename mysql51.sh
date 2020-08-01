#!/bin/sh
set -euo pipefail

SOURCE=`pwd`
MDATA="/data/mysql/MYSQL51"
INSDIR="mysql51"
PWSD_MYSQL="admin"
MYSQLDIR="/usr/local/$INSDIR"
PORT="3307"

MYVER="5.1.51"

mkdir -p $MDATA
mkdir $MDATA/data
mkdir $MDATA/log
touch $MDATA/log/mysql_slow.log
touch $MDATA/log/server_log.log

yum -y install gcc-c++ openssl openssl-devel cmake git wget bzip2 unzip libedit-devel libaio-devel perl libedit libtool which && yum -y clean all

cd $SOURCE
adduser -d /nonexistent -s /sbin/nologin mysql

#install ncurses lib
wget https://ftp.gnu.org/pub/gnu/ncurses/ncurses-6.1.tar.gz
tar xzf ncurses-6.1.tar.gz
cd ncurses-6.1
./configure --prefix=/opt/ncurses
make
make install

#download and configure mysql5.1
cd $SOURCE
wget http://dev.mysql.com/get/Downloads/MySQL-5.1/mysql-5.1.51.tar.gz
tar -xzvf mysql-$MYVER.tar.gz
cd mysql-$MYVER

./configure --enable-profiling --prefix=/usr/local/$INSDIR --enable-local-infile \
 --datadir=$MDATA/data \
 --with-mysqld-user=mysql  --with-big-tables \
 --with-plugins=partition,blackhole,federated,heap,innodb_plugin --without-docs \
 --with-named-curses-libs=/opt/ncurses/lib/libncurses.a \
 --with-tcp-port=$PORT \
 --with-unix-socket-path=/tmp/mysqld_mysql51.sock \
 --with-archivestorage-engine \

make
make install

rm /etc/my.cnf -rf
echo "[mysqld]
socket 	= /tmp/mysqld_mysql51.sock
port	= 3307
bind-address = 0.0.0.0	
#skip-networking
basedir = /usr/local/$INSDIR
datadir = $MDATA/data
expire-logs-days=2
long_query_time=3
log_bin=$MDATA/log/mysql-bin
server-id=1
"> /usr/local/$INSDIR/my.cnf

./scripts/mysql_install_db --user=mysql --datadir=$MDATA/data

# start up service
/bin/cp -rf support-files/mysql.server /etc/init.d/$INSDIR
chmod +x /etc/init.d/$INSDIR
chkconfig --add $INSDIR
chkconfig $INSDIR on

rm -rf /usr/bin/$INSDIR
ln -s /usr/local/$INSDIR/bin/mysql /usr/bin/$INSDIR

cd /usr/local
chown -R mysql.mysql $INSDIR -R
chown -R mysql.mysql $MDATA

#/usr/local/$INSDIR/scripts/mysql_install_db --user=mysql --basedir=/usr/local/$INSDIR --datadir=$MDATA/data
service $INSDIR start

/usr/local/$INSDIR/bin/mysql -uroot -S /tmp/mysqld_mysql51.sock -e "SET PASSWORD FOR 'root'@'localhost' = PASSWORD('$PWSD_MYSQL');"
/usr/local/$INSDIR/bin/mysql -uroot --password="$PWSD_MYSQL" -S /tmp/mysqld_mysql51.sock -e "create user 'root'@'%' IDENTIFIED BY '$PWSD_MYSQL'; grant all privileges on *.* to 'root'@'%' with grant option; flush privileges;"
