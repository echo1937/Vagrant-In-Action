SET GLOBAL validate_password.policy=LOW;
ALTER USER 'root'@'localhost' IDENTIFIED BY 'redhat.com';
CREATE USER 'exporter'@'localhost' IDENTIFIED BY 'XXXXXXXX' WITH MAX_USER_CONNECTIONS 3;
GRANT PROCESS, REPLICATION CLIENT, SELECT ON *.* TO 'exporter'@'localhost';