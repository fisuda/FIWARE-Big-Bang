#!/bin/bash
set -e

# usage: file_env VAR [DEFAULT]
#    ie: file_env 'XYZ_DB_PASSWORD' 'example'
# (will allow for "$XYZ_DB_PASSWORD_FILE" to fill in the value of
#  "$XYZ_DB_PASSWORD" from a file, especially for Docker's secrets feature)
file_env() {
	local var="$1"
	local fileVar="${var}_FILE"
	local def="${2:-}"
	if [ "${!var:-}" ] && [ "${!fileVar:-}" ]; then
		echo >&2 "error: both $var and $fileVar are set (but are exclusive)"
		exit 1
	fi
	local val="$def"
	if [ "${!var:-}" ]; then
		val="${!var}"
	elif [ "${!fileVar:-}" ]; then
		val="$(< "${!fileVar}")"
	fi
	export "$var"="$val"
	unset "$fileVar"
}

change_value() {
	touch $INIT_PROP_FILE_TEMP
	local label="$1"
	local value_check="$2"
	tr -d '\n' < $INIT_PROP_FILE | sed 's#/>#/>\n#g' | sed 's/valueCheck=/\x00/g' | sed -E "s#(label=\"${label}\"[^\x00]*\x00)\"[^\"]*#\1\"${value_check}#g" | sed 's/\x00/valueCheck=/g' > $INIT_PROP_FILE_TEMP && mv $INIT_PROP_FILE_TEMP $INIT_PROP_FILE
}

file_env "DB_HOST"
file_env "DB_PORT"
file_env "DB_DB"
file_env "DB_USER"
file_env "DB_PASS"

file_env "CACHE_DB_HOST"
file_env "CACHE_DB_PORT"
file_env "CACHE_DB_DB"
file_env "CACHE_DB_USER"
file_env "CACHE_DB_PASS"

file_env "AJP_SECRET"

file_env "HAZELCAST_HOSTS"
file_env "HAZELCAST_PORT"

# Wait for MySql
./wait-for-it.sh ${DB_HOST}:${DB_PORT} -- echo "MySql is up!"

# Placeholder created after the first boot of the container
CONTAINER_INITIALIZED_PLACEHOLDER=/.CONTAINER_INITIALIZED

# Check if this is the first boot
if [ ! -f "$CONTAINER_INITIALIZED_PLACEHOLDER" ]
then
	file_env "HMAC_KEY"
	file_env "PASSWORD_ENCRYPTION_SECRET"
	file_env "PUBLIC_ADDRESS"

        if [ "${OAUTH2}" = "keyrock" ]; then

                INIT_PROP_FILE=${KNOWAGE_DIRECTORY}/${APACHE_TOMCAT_PACKAGE}/webapps/knowage/WEB-INF/classes/it/eng/spagobi/commons/initializers/metadata/config/configs.xml
                INIT_PROP_FILE_TEMP=${KNOWAGE_DIRECTORY}/webapps/knowage/WEB-INF/classes/it/eng/spagobi/commons/initializers/metadata/config/configs.xml.temp
                SERVER_CONF=${KNOWAGE_DIRECTORY}/conf/server.xml
                WEB_XML=${KNOWAGE_DIRECTORY}/webapps/knowage/WEB-INF/web.xml
                KNOWAGE_JAR=${KNOWAGE_DIRECTORY}/webapps/knowage/WEB-INF/lib/knowage-utils-7.0.0.jar
                UNZIPPED_JAR=knowageJAR
                KNOWAGE_CONF=${UNZIPPED_JAR}/it/eng/spagobi/security/OAuth2/configs.properties
                INITIALIZER_XML=${KNOWAGE_DIRECTORY}/webapps/knowage/WEB-INF/conf/config/initializers.xml

	        change_value "SPAGOBI_SSO.ACTIVE" "true"
	        change_value "SPAGOBI.SECURITY.PORTAL-SECURITY-CLASS.className" "it.eng.spagobi.security.OAuth2SecurityInfoProvider"
	        change_value "SPAGOBI.SECURITY.USER-PROFILE-FACTORY-CLASS.className" "it.eng.spagobi.security.OAuth2SecurityServiceSupplier"
	        change_value "SPAGOBI_SSO.SECURITY_LOGOUT_URL" "https://keyrock.mydomain.de/auth/external_logout"
	
	        sed -i "s/it.eng.spagobi.services.common.FakeSsoService/it.eng.spagobi.services.oauth2.Oauth2SsoService/g" $SERVER_CONF
	        sed -i "s/it.eng.spagobi.commons.initializers.metadata.MetadataInitializer/it.eng.spagobi.commons.initializers.metadata.OAuth2MetadataInitializer/g" $INITIALIZER_XML
	        sed -i "s/<!-- START OAUTH 2/<!-- START OAUTH 2 -->/g" $WEB_XML
	        sed -i "s/END OAUTH 2 -->/<!-- END OAUTH 2 -->/g" $WEB_XML

	        unzip $KNOWAGE_JAR -d $UNZIPPED_JAR
	        sed -i "s/CLIENT_ID.*/CLIENT_ID=${CLIENT_ID}/g" $KNOWAGE_CONF
	        sed -i "s/SECRET.*/SECRET=${CLIENT_SECRET}/g" $KNOWAGE_CONF
	        sed -i "s#AUTHORIZE_URL.*#AUTHORIZE_URL=${KEYROCK_URL}/oauth2/authorize#g" $KNOWAGE_CONF
	        sed -i "s#ACCESS_TOKEN_URL.*#ACCESS_TOKEN_URL=${KEYROCK_URL}/oauth2/token#g" $KNOWAGE_CONF
	        sed -i "s#USER_INFO_URL.*#USER_INFO_URL=${KEYROCK_URL}/user#g" $KNOWAGE_CONF
	        sed -i "s#REDIRECT_URI.*#REDIRECT_URI=${KEYROCK_REDIRECT_URI}#g" $KNOWAGE_CONF
	        sed -i "s#TOKEN_PATH.*#TOKEN_PATH=${KEYROCK_TOKEN_PATH}#g" $KNOWAGE_CONF

                sed -i "s#REST_BASE_URL.*#REST_BASE_URL=${KEYROCK_URL}/#g" $KNOWAGE_CONF
	
	        sed -i "s#APPLICATION_ID.*#APPLICATION_ID=${KEYROCK_APPLICATION_ID}#g"
	        sed -i "s/ADMIN_ID.*/ADMIN_ID=${KEYROCK_ADMIN_ID}/g"
	        sed -i "s/ADMIN_EMAIL.*/ADMIN_EMAIL=${KEYROCK_ADMIN_EMAIL}/g"
	        sed -i "s/ADMIN_PASSWORD.*/ADMIN_PASSWORD=${KEYROCK_ADMIN_PASSWORD}/g"
	        cd $UNZIPPED_JAR; zip -r $KNOWAGE_JAR *
	        cd ..
	
        fi

	# Generate default values for the optional env vars
	if [[ -z "$PUBLIC_ADDRESS" ]]
	then
	        #get the address of container
	        #example : default via 172.17.42.1 dev eth0 172.17.0.0/16 dev eth0 proto kernel scope link src 172.17.0.109
	        PUBLIC_ADDRESS=`ip route | grep src | awk '{print $9}'`
	fi
	
	if [ -z "$HMAC_KEY" ]
	then
		echo "The HMAC_KEY environment variable is needed"
		exit -1
	fi
	
	if [ -z "$PASSWORD_ENCRYPTION_SECRET" ]
	then
		echo "The PASSWORD_ENCRYPTION_SECRET environment variable is needed"
		exit -1
	fi
	
	if [ -z "$DB_HOST" ] || [ -z "$DB_PORT" ] || [ -z "$DB_DB"   ] || [ -z "$DB_USER" ] || [ -z "$DB_PASS" ]
	then
		echo "The DB_HOST, DB_PORT, DB_DB, DB_USER, DB_PASS environment variables are needed"
		exit -1
	fi

	if [ -z "$CACHE_DB_HOST" ] || [ -z "$CACHE_DB_PORT" ] || [ -z "$CACHE_DB_DB"   ] || [ -z "$CACHE_DB_USER" ] || [ -z "$CACHE_DB_PASS" ]
	then
		echo "The CACHE_DB_HOST, CACHE_DB_PORT, CACHE_DB_DB, CACHE_DB_USER, CACHE_DB_PASS environment variables are needed"
		exit -1
	fi

	if [ -z "$AJP_SECRET" ]
	then
		AJP_SECRET=$( openssl rand -base64 32 )
		echo "###################################################################"
		echo "#"
		echo "# Random generated AJP secret:"
		echo "#   ${AJP_SECRET}"
		echo "#"
	fi

	if [ -z "$HAZELCAST_HOSTS" ]
	then
		HAZELCAST_HOSTS="127.0.0.1"
		echo "###################################################################"
		echo "#"
		echo "# The HAZELCAST_HOSTS environment not present. Knowage will launch "
		echo "# one internally."
		echo "#"
	fi

	if [ -z "$HAZELCAST_PORT" ]
	then
		HAZELCAST_PORT="5701"
	fi

	# Replace the address of container inside server.xml
	sed -i "s|http:\/\/.*:8080|http:\/\/${PUBLIC_ADDRESS}:8080|g" ${KNOWAGE_DIRECTORY}/apache-tomcat/conf/server.xml
	sed -i "s|http:\/\/.*:8080\/knowage|http:\/\/localhost:8080\/knowage|g" ${KNOWAGE_DIRECTORY}/apache-tomcat/conf/server.xml
	sed -i "s|http:\/\/localhost:8080|http:\/\/${PUBLIC_ADDRESS}:8080|g" ${KNOWAGE_DIRECTORY}/apache-tomcat/webapps/knowage/WEB-INF/web.xml
	
	# Insert knowage metadata into db if it doesn't exist
	result=`mysql -h${DB_HOST} -P${DB_PORT} -u${DB_USER} -p${DB_PASS} ${DB_DB} -e "SHOW TABLES LIKE '%SBI_%';"`
	if [ -z "$result" ]; then
		mysql -h${DB_HOST} -P${DB_PORT} -u${DB_USER} -p${DB_PASS} ${DB_DB} --execute="source ${MYSQL_SCRIPT_DIRECTORY}/MySQL_create.sql"
		mysql -h${DB_HOST} -P${DB_PORT} -u${DB_USER} -p${DB_PASS} ${DB_DB} --execute="source ${MYSQL_SCRIPT_DIRECTORY}/MySQL_create_quartz_schema.sql"
	fi
	
	# Set DB connection for Knowage metadata
	xmlstarlet ed -P -L \
		-u "//Server/GlobalNamingResources/Resource[@name='jdbc/knowage']/@url"      -v "jdbc:mysql://${DB_HOST}:${DB_PORT}/${DB_DB}" \
		-u "//Server/GlobalNamingResources/Resource[@name='jdbc/knowage']/@username" -v "${DB_USER}" \
		-u "//Server/GlobalNamingResources/Resource[@name='jdbc/knowage']/@password" -v "${DB_PASS}" \
		${KNOWAGE_DIRECTORY}/apache-tomcat/conf/server.xml
	
	# Set DB connection for Knowage cache
	xmlstarlet ed -P -L \
		-u "//Server/GlobalNamingResources/Resource[@name='jdbc/ds_cache']/@url"      -v "jdbc:mysql://${CACHE_DB_HOST}:${CACHE_DB_PORT}/${CACHE_DB_DB}" \
		-u "//Server/GlobalNamingResources/Resource[@name='jdbc/ds_cache']/@username" -v "${CACHE_DB_USER}" \
		-u "//Server/GlobalNamingResources/Resource[@name='jdbc/ds_cache']/@password" -v "${CACHE_DB_PASS}" \
		${KNOWAGE_DIRECTORY}/apache-tomcat/conf/server.xml

	# Set HMAC key
	xmlstarlet ed -P -L \
		-u "//Server/GlobalNamingResources/Environment[@name='hmacKey']/@value" -v "${HMAC_KEY}" \
		${KNOWAGE_DIRECTORY}/apache-tomcat/conf/server.xml
	
	# Set password encryption key
	echo $PASSWORD_ENCRYPTION_SECRET > ${KNOWAGE_DIRECTORY}/apache-tomcat/conf/passwordEncryptionSecret

	# Set AJP secret
	xmlstarlet ed -P -L \
		-d "//Server/Service/Connector[contains(@protocol, 'AJP')]/@secretRequired" \
		${KNOWAGE_DIRECTORY}/apache-tomcat/conf/server.xml
	xmlstarlet ed -P -L \
		-d "//Server/Service/Connector[contains(@protocol, 'AJP')]/@secret" \
		${KNOWAGE_DIRECTORY}/apache-tomcat/conf/server.xml
	xmlstarlet ed -P -L \
		-i "//Server/Service/Connector[contains(@protocol, 'AJP')]" -t attr -n secretRequired -v "true" \
		${KNOWAGE_DIRECTORY}/apache-tomcat/conf/server.xml
	xmlstarlet ed -P -L \
		-i "//Server/Service/Connector[contains(@protocol, 'AJP')]" -t attr -n secret -v "${AJP_SECRET}" \
		${KNOWAGE_DIRECTORY}/apache-tomcat/conf/server.xml
	
	# Setting hazelcast.xml
	# 
	# N.B.: the _ in Xmlstarlet XPath stands for default namespace

	# Set port
	xmlstarlet ed -P -L \
		-u "/_:hazelcast/_:network/_:port" -v ${HAZELCAST_PORT} \
		${KNOWAGE_DIRECTORY}/apache-tomcat/conf/hazelcast.xml

	# Clean up the member list
	xmlstarlet ed -P -L \
		-d "/_:hazelcast/_:network/_:join/_:tcp-ip/_:member-list/_:member" \
		${KNOWAGE_DIRECTORY}/apache-tomcat/conf/hazelcast.xml
	
	# Set the actual member list
	echo -n "${HAZELCAST_HOSTS}" | xargs -d "," -n 1 -i"{}" \
		xmlstarlet ed -P -L \
			-s "/_:hazelcast/_:network/_:join/_:tcp-ip/_:member-list" -t elem -n member -v \{\} \
			${KNOWAGE_DIRECTORY}/apache-tomcat/conf/hazelcast.xml

	# Format
	xmlstarlet ed -O -L ${KNOWAGE_DIRECTORY}/apache-tomcat/conf/hazelcast.xml

	# Create the placeholder to prevent multiple initializations
	touch "$CONTAINER_INITIALIZED_PLACEHOLDER"
fi

exec "$@"
