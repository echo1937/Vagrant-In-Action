export DATA_SOURCE_NAME='exporter:XXXXXXXX@(prometheus:3306)/'
chmod u+x /vagrant/mysqld_exporter/mysqld_exporter
nohup /vagrant/mysqld_exporter/mysqld_exporter >> /tmp/mysqld_exporter.out 2>&1 &