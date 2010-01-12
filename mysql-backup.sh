#!/bin/sh

export d=`date +'%Y-%m-%d'`
mkdir -p /opt/backup/
mysqldump --add-drop-table --allow-keywords -q -a -c --single-transaction -u root --password= databasename > /opt/backup/$d.sql
gzip /opt/backup/$d.sql
