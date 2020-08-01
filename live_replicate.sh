#!/bin/bash
set -euo pipefail

DUMP_FILE="/tmp/export-$(date +"%d%m%Y").sql"

#MASTER
MIP="192.168.14.54"
MPORT="3307"
MUSER="root"
MPWD="admin"
MDATA="/data/mysql/MYSQL51"
MRUN="/data/mysql/MYSQL51/data/mysql/mysql.server"
MBIN="/usr/local/mysql51/bin/mysql"
MMYSQLDUMP="/usr/local/mysql51/bin/mysqldump"
RUSER="repl"
RPWD="slavepassword"
#MSERVER-ID="1"

#SLAVE
SIP="192.168.14.55"
SPORT="3307"
SUSER="root"
SPWD="admin"
SDATA="/data/mysql/MYSQL51"
SRUN="/data/mysql/MYSQL51/data/mysql/mysql.server"
SBIN="/usr/local/mysql51/bin/mysql"
SLAVE_OK="OK"
#SSERVER-ID="2"

#############

#create user replicate to
$MBIN "-u$MUSER" "-p$MPWD" <<-EOSQL &
CREATE USER '$RUSER'@'%' IDENTIFIED BY '$RPWD';
GRANT REPLICATION SLAVE ON *.* TO '$RUSER'@'%';
FLUSH PRIVILEGES;
FLUSH TABLES WITH READ LOCK;
EOSQL

#echo "Waiting for database to be locked"
sleep 3

# Dump the database (to the client executing this script) while it is locked
echo "  - Dumping database to $DUMP_FILE"
$MMYSQLDUMP "-u$MUSER" "-p$MPWD" --all-database --master-data > $DUMP_FILE
echo "  - Dump completed."

echo "Get LOG_FILE and LOG_POS of Master"
MASTER_STATUS=$($SBIN -uroot --password="$MPWD" --port=$MPORT -ANe "SHOW MASTER STATUS\G;" | awk '{print $1 " " $2}')
LOG_FILE=$(echo $MASTER_STATUS | cut -f3 -d ' ')
LOG_POS=$(echo $MASTER_STATUS | cut -f4 -d ' ')
echo "Current log file is $LOG_FILE and log position is $LOG_POS"

#When finished, unlock table
$MBIN "-u$MUSER" "-p$MPWD" <<-EOSQL &
UNLOCK TABLES;
EOSQL
echo "Master database unlocked"

echo "Slave: $SIP"
echo "Copy file dump from Master to Slave"
rsync -avz --delete $DUMP_FILE root@$SIP:$DUMP_FILE

echo "---Config Slave---"
ssh root@$SIP <<END_SCRIPT1

echo "Import and start slave"
$SBIN "-u$SUSER" "-p$SPWD" < $DUMP_FILE

echo "Setting up slave replication on Slave"
$SBIN "-u$SUSER" "-p$SPWD" <<-EOSQL1 &
STOP SLAVE;
CHANGE MASTER TO MASTER_HOST='$MIP',
MASTER_USER='$RUSER',
MASTER_PASSWORD='$RPWD',
MASTER_PORT=$MPORT,
MASTER_LOG_FILE='$LOG_FILE',
MASTER_LOG_POS=$LOG_POS;
START SLAVE;

EOSQL1

#Wait for slave to get started and have the correct status
sleep 2

#Check if replication status is OK
SLAVE_OK=$($SBIN "-u$SUSER" "-p$SPWD" -e "SHOW SLAVE STATUS\G;" | grep "Slave_IO_Running: Yes")
if [ -z "$SLAVE_OK" ]; then
        echo "Slave_IO is not running"
else
        echo "Slave_IO is running"
fi      
exit
END_SCRIPT1



##master info
tmp_db="tmp$(date +"%Y%m%d%H%M")"
$MBIN "-u$MUSER" "-p$MPWD" -e "CREATE DATABASE $tmp_db;"
$MBIN "-u$MUSER" "-p$MPWD" -e "SHOW DATABASES;"
$MBIN "-u$MUSER" "-p$MPWD" -e "SHOW MASTER STATUS\G;"

##test on slave
$SBIN "-u$SUSER" "-p$SPWD" --port=$SPORT -h $SIP -e "SHOW DATABASES\G;"
$SBIN "-u$SUSER" "-p$SPWD" --port=$SPORT -h $SIP -e "SHOW SLAVE STATUS\G;"
$SBIN "-u$SUSER" "-p$SPWD" --port=$SPORT -h $SIP -e "SHOW PROCESSLIST\G;"
