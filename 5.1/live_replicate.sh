#!/bin/bash
set -euo pipefail

#MASTER info
MIP="192.168.14.54"
MPORT="3307"
MUSER="root"
MPWD="admin"
MDATA="/data/mysql/MYSQL51"
MRUN="/etc/init.d/mysql51"
MBIN="/usr/local/mysql51/bin/mysql"
MMYSQLDUMP="/usr/local/mysql51/bin/mysqldump"
RUSER="repl"
RPWD="slavepassword"
#MSERVER-ID="1"

#SLAVE info
SIP="192.168.14.61"
SPORT="3307"
SUSER="root"
SPWD="admin"
SDATA="/data/mysql/MYSQL51"
SBIN="/usr/local/mysql51/bin/mysql"
SRUN="/etc/init.d/mysql51"
SLAVE_OK="OK"
#SSERVER-ID="2"


echo "Create user *$RUSER* to replicate to"
$MBIN "-u$MUSER" "-p$MPWD" <<-EOSQL &
CREATE USER '$RUSER'@'%' IDENTIFIED BY '$RPWD';
GRANT REPLICATION SLAVE ON *.* TO '$RUSER'@'%';
FLUSH PRIVILEGES;
EOSQL

####################
#############
echo "Starting setup Replication for MASTER:$MIP and SLAVE:$SIP."
echo "1. Stop Master"
$MRUN stop
echo "MYSQL on MASTER machine has been stopped"

echo "2. Stop Slave"
ssh root@$SIP <<END_SCRIPT
$SBIN "-u$SUSER" "-p$SPWD" -e "STOP SLAVE\G;"
$SRUN stop
echo "MYSQL on slave machine has been stopped"
exit
END_SCRIPT

echo "3. Start to truncate Slave and Master"

echo "Truncate log file on Master"
rm -rf $MDATA/log/*
echo "Truncate log files on Master completed"

echo "Truncate databases and logs on Slave"
ssh root@$SIP <<END_SCRIPT
rm $SDATA/log/* -rf
rm $SDATA/data/* -rf
echo "Delete logs and databases on slave completed"
$SBIN "-u$SUSER" "-p$SPWD" -e "STOP SLAVE\G;"
$SRUN stop
echo "MYSQL on slave machine has been stopped"
exit
END_SCRIPT


# Sync database
echo "Syncing databases to slave" #Deletes files in the destination directory if they don't exist in the source directory
rsync -avz --delete $MDATA/data/ root@$SIP:$SDATA/data
echo "Sync databases completed"

echo "5. Starting MYSQL on master"
$MRUN start
sleep 2


#Get master info
echo "Get LOG_FILE and LOG_POS of MASTER"
MASTER_STATUS=$($SBIN -uroot --password="$MPWD" --port=$MPORT -ANe "SHOW MASTER STATUS\G;" | awk '{print $1 " " $2}')
LOG_FILE=$(echo $MASTER_STATUS | cut -f3 -d ' ')
LOG_POS=$(echo $MASTER_STATUS | cut -f4 -d ' ')
echo "Current log file is $LOG_FILE and log position is $LOG_POS"


echo "6. Start MYSQL on Slave "
ssh root@$SIP <<END_SCRIPT1
echo "Starting MYSQL on slave"
$SRUN start
echo "Setting up slave replication on Slave to accept $MIP as Master"
$SBIN "-u$SUSER" "-p$SPWD" <<-EOSQL1 &
STOP SLAVE;
CHANGE MASTER TO MASTER_HOST='$MIP',
MASTER_USER='$RUSER',
MASTER_PASSWORD='$RPWD',
MASTER_PORT=$MPORT,
MASTER_LOG_FILE='$LOG_FILE',
MASTER_LOG_POS=$LOG_POS;
FLUSH PRIVILEGES;
START SLAVE;
EOSQL1

echo "Setup slave config completed"
#Wait for slave to get started and have the correct status
sleep 2

echo "Checking SLAVE status"
SLAVE_OK=$($SBIN "-u$SUSER" "-p$SPWD" -e "SHOW SLAVE STATUS\G;" | grep "Slave_IO_Running: Yes")
if [ -z "$SLAVE_OK" ]; then
        echo "Slave_IO is not running"
else
        echo "Slave_IO is running"
fi
exit
END_SCRIPT1

##master info
echo "Checking MASTER status"
$MBIN "-u$MUSER" "-p$MPWD" -e "SHOW MASTER STATUS\G;"

##test on slave
echo "Checking SLAVE status"
ssh root@$SIP <<END_SCRIPT2
echo "Current databases list on Slave:"
$SBIN "-u$SUSER" "-p$SPWD" --port=$SPORT -e "SHOW DATABASES\G;"
echo "Slave status:"
$SBIN "-u$SUSER" "-p$SPWD" --port=$SPORT -e "SHOW SLAVE STATUS\G;"
echo "Process list"
$SBIN "-u$SUSER" "-p$SPWD" --port=$SPORT -e "SHOW PROCESSLIST\G;"
END_SCRIPT2
