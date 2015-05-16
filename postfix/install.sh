debconf-set-selections <<< "postfix postfix/mailname string $HOSTNAME"
debconf-set-selections <<< "postfix postfix/main_mailer_type string 'Internet Site'"

apt-get install postfix postfix-mysql -y

mysqladmin -uroot -p$PASSWORD create mailserver	
mysql -uroot -p$PASSWORD << EOF
GRANT SELECT ON mailserver.* TO 'mailuser'@'127.0.0.1' IDENTIFIED BY 'mailuserpass';
FLUSH PRIVILEGES;
USE mailserver;
CREATE TABLE \`virtual_domains\` (
  \`id\` int(11) NOT NULL auto_increment,
  \`name\` varchar(50) NOT NULL,
  PRIMARY KEY (\`id\`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE \`virtual_users\` (
  \`id\` int(11) NOT NULL auto_increment,
  \`domain_id\` int(11) NOT NULL,
  \`password\` varchar(106) NOT NULL,
  \`email\` varchar(100) NOT NULL,
  PRIMARY KEY (\`id\`),
  UNIQUE KEY \`email\` (\`email\`),
  FOREIGN KEY (domain_id) REFERENCES virtual_domains(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE \`virtual_aliases\` (
  \`id\` int(11) NOT NULL auto_increment,
  \`domain_id\` int(11) NOT NULL,
  \`source\` varchar(100) NOT NULL,
  \`destination\` varchar(100) NOT NULL,
  PRIMARY KEY (\`id\`),
  FOREIGN KEY (domain_id) REFERENCES virtual_domains(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;


INSERT INTO \`mailserver\`.\`virtual_domains\` (\`id\` ,\`name\`) 
VALUES('1', '$HOSTNAME');
  
INSERT INTO \`mailserver\`.\`virtual_users\` (\`id\`, \`domain_id\`, \`password\` , \`email\`)
VALUES ('1', '1', '\$1\$pfhfftkU\$3/0sv66/HiM0Dn6l3qRiq/', 'admin@$HOSTNAME');
# This password $1$pfhfftkU$3/0sv66/HiM0Dn6l3qRiq/ IS 123456 
# note must escape \$ in that way in linux EOP  

INSERT INTO \`mailserver\`.\`virtual_aliases\` (\`id\`, \`domain_id\`, \`source\`, \`destination\`)
VALUES('1', '1', 'alias@$HOSTNAME', 'admin@$HOSTNAME');
EOF

cp /etc/postfix/main.cf /etc/postfix/main.cf.orig

postconf -e mydestination=localhost
postconf -# smtpd_tls_session_cache_database
postconf -# smtp_tls_session_cache_database
postconf -e smtpd_tls_cert_file=/etc/dovecot/dovecot.pem
postconf -e smtpd_tls_key_file=/etc/dovecot/private/dovecot.pem
postconf -e smtpd_use_tls=yes
postconf -e smtpd_tls_auth_only=yes
postconf -e smtpd_sasl_type=dovecot
postconf -e smtpd_sasl_path=private/auth
postconf -e smtpd_sasl_auth_enable=yes
postconf -e smtpd_recipient_restrictions=permit_sasl_authenticated,permit_mynetworks,reject_unauth_destination
postconf -e virtual_transport=lmtp:unix:private/dovecot-lmtp
postconf -e virtual_mailbox_domains=mysql:/etc/postfix/mysql-virtual-mailbox-domains.cf
postconf -e virtual_mailbox_maps=mysql:/etc/postfix/mysql-virtual-mailbox-maps.cf
postconf -e virtual_alias_maps=mysql:/etc/postfix/mysql-virtual-alias-maps.cf	

function postfix_mysql_file {
	echo "user = mailuser
password = mailuserpass
hosts = 127.0.0.1
dbname = mailserver 
$1 " > $2
}

cd /etc/postfix/
postfix_mysql_file "query = SELECT 1 FROM virtual_domains WHERE name='%s'" mysql-virtual-mailbox-domains.cf
postfix_mysql_file "query = SELECT 1 FROM virtual_users WHERE email='%s'" mysql-virtual-mailbox-maps.cf
postfix_mysql_file "query = SELECT destination FROM virtual_aliases WHERE source='%s'" mysql-virtual-alias-maps.cf

service postfix restart