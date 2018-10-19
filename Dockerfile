FROM ubuntu:14.04

# Set version and github repo which you want to build from
ENV GITHUB_OWNER druid-io
ENV DRUID_VERSION 0.13.0-incubating-SNAPSHOT
ENV ZOOKEEPER_VERSION 3.4.10
ENV KAFKA_VERSION=1.1.1

# Java 8
RUN apt-get update \
      && apt-get install -y software-properties-common \
      && apt-add-repository -y ppa:webupd8team/java \
      && apt-get purge --auto-remove -y software-properties-common \
      && apt-get update \
      && echo oracle-java-8-installer shared/accepted-oracle-license-v1-1 select true | /usr/bin/debconf-set-selections \
      && apt-get install -y oracle-java8-installer oracle-java8-set-default \
                            mysql-server \
                            supervisor \
      && apt-get clean \
      && rm -rf /var/cache/oracle-jdk8-installer \
      && rm -rf /var/lib/apt/lists/*

# Zookeeper
RUN wget -q -O - http://www-eu.apache.org/dist/zookeeper/zookeeper-$ZOOKEEPER_VERSION/zookeeper-$ZOOKEEPER_VERSION.tar.gz | tar -xzf - -C /usr/local \
      && cp /usr/local/zookeeper-$ZOOKEEPER_VERSION/conf/zoo_sample.cfg /usr/local/zookeeper-$ZOOKEEPER_VERSION/conf/zoo.cfg \
      && ln -s /usr/local/zookeeper-$ZOOKEEPER_VERSION /usr/local/zookeeper

# Kafka
RUN wget -q -O - http://www-eu.apache.org/dist/kafka/$KAFKA_VERSION/kafka_2.12-$KAFKA_VERSION.tgz | tar -xzf - -C /usr/local \
      && ln -s /usr/local/kafka_2.12-$KAFKA_VERSION /usr/local/kafka \
      && mkdir -p /usr/local/kafka/logs \
      && chown daemon /usr/local/kafka/logs

# Druid system user
RUN adduser --system --group --no-create-home druid \
      && mkdir -p /var/lib/druid \
      && chown druid:druid /var/lib/druid

# Druid (from source)
RUN mkdir -p /usr/local/druid

# Install Druid from local disk

ADD druid /usr/local/druid/

WORKDIR /

# Setup metadata store and add sample data
ADD sample-data.sql sample-data.sql
RUN find /var/lib/mysql -type f -exec touch {} \; \
      && /etc/init.d/mysql start \
      && mysql -u root -e "GRANT ALL ON druid.* TO 'druid'@'localhost' IDENTIFIED BY 'diurd'; CREATE database druid CHARACTER SET utf8;" \
      && java -cp /usr/local/druid/lib/druid-services-*-selfcontained.jar \
          -Ddruid.extensions.directory=/usr/local/druid/extensions \
          -Ddruid.extensions.loadList=[\"mysql-metadata-storage\"] \
          -Ddruid.metadata.storage.type=mysql \
          org.apache.druid.cli.Main tools metadata-init \
              --connectURI="jdbc:mysql://localhost:3306/druid" \
              --user=druid --password=diurd \
      && mysql -u root druid < sample-data.sql \
      && /etc/init.d/mysql stop

# Setup supervisord
ADD supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Expose ports:
# - 8081: HTTP (coordinator)
# - 8082: HTTP (broker)
# - 8083: HTTP (historical)
# - 8090: HTTP (overlord)
# - 3306: MySQL
# - 2181 2888 3888: ZooKeeper
# - 9092: Kafka
EXPOSE 8081
EXPOSE 8082
EXPOSE 8083
EXPOSE 8090
EXPOSE 3306
EXPOSE 2181 2888 3888
EXPOSE 9092

WORKDIR /var/lib/druid
ENTRYPOINT export HOSTIP="$(resolveip -s $HOSTNAME)" && find /var/lib/mysql -type f -exec touch {} \; && exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
