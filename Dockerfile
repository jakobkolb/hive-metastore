FROM openjdk:21-slim

# Lifted from: https://github.com/joshuarobinson/presto-on-k8s/blob/1c91f0b97c3b7b58bdcdec5ad6697b42e50d74c7/hive_metastore/Dockerfile

# see https://hadoop.apache.org/releases.html
ARG HADOOP_VERSION=3.3.0
# see https://downloads.apache.org/hive/
ARG HIVE_METASTORE_VERSION=3.0.0
# see https://jdbc.postgresql.org/download.html#current
ARG POSTGRES_CONNECTOR_VERSION=42.2.18

# Set necessary environment variables.
ENV HADOOP_HOME="/opt/hadoop"
ENV PATH="/opt/spark/bin:/opt/hadoop/bin:${PATH}"
ENV DATABASE_DRIVER=org.postgresql.Driver
ENV DATABASE_TYPE=postgres
ENV DATABASE_TYPE_JDBC=postgresql
ENV DATABASE_PORT=5432

WORKDIR /app
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# hadolint ignore=DL3008
RUN \
  echo "Install OS dependencies" && \
    build_deps="curl" && \
    apt-get update -y && \
    apt-get install -y $build_deps --no-install-recommends
RUN \
  echo "Download and extract the Hadoop binary package" && \
    curl https://archive.apache.org/dist/hadoop/core/hadoop-$HADOOP_VERSION/hadoop-$HADOOP_VERSION.tar.gz \
    | tar xvz -C /opt/ && \
    ln -s /opt/hadoop-$HADOOP_VERSION /opt/hadoop && \
    rm -r /opt/hadoop/share/doc
RUN \
  echo "Add S3a jars to the classpath using this hack" && \
    ln -s /opt/hadoop/share/hadoop/tools/lib/hadoop-aws* /opt/hadoop/share/hadoop/common/lib/ && \
    ln -s /opt/hadoop/share/hadoop/tools/lib/aws-java-sdk* /opt/hadoop/share/hadoop/common/lib/
RUN \
  echo "Download and install the standalone metastore binary" && \
    curl https://downloads.apache.org/hive/hive-standalone-metastore-$HIVE_METASTORE_VERSION/hive-standalone-metastore-$HIVE_METASTORE_VERSION-bin.tar.gz \
    | tar xvz -C /opt/ && \
    ln -s /opt/apache-hive-metastore-$HIVE_METASTORE_VERSION-bin /opt/hive-metastore
RUN \
  echo "Fix 'java.lang.NoSuchMethodError: com.google.common.base.Preconditions.checkArgument'" && \
  echo "Keep this until this lands: https://issues.apache.org/jira/browse/HIVE-22915" && \
    rm /opt/apache-hive-metastore-$HIVE_METASTORE_VERSION-bin/lib/guava-19.0.jar && \
    cp /opt/hadoop-$HADOOP_VERSION/share/hadoop/hdfs/lib/guava-27.0-jre.jar /opt/apache-hive-metastore-$HIVE_METASTORE_VERSION-bin/lib/
RUN \
  echo "Download and install the database connector" && \
    curl -L https://jdbc.postgresql.org/download/postgresql-$POSTGRES_CONNECTOR_VERSION.jar --output /opt/postgresql-$POSTGRES_CONNECTOR_VERSION.jar && \
    ln -s /opt/postgresql-$POSTGRES_CONNECTOR_VERSION.jar /opt/hadoop/share/hadoop/common/lib/ && \
    ln -s /opt/postgresql-$POSTGRES_CONNECTOR_VERSION.jar /opt/hive-metastore/lib/
RUN \
  echo "Purge build artifacts" && \
#    apt-get purge -y --auto-remove $build_deps && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

COPY run.sh run.sh


# Add custom certificates to the JVM trust store
RUN mkdir -p /tmp/certs
COPY certs/* /tmp/certs/

# Add custom certificates to ca-certificates.crt
RUN cat /tmp/certs/root-CA.crt /tmp/certs/sub-02-CA.crt /tmp/certs/powerscale.crt >> /etc/ssl/certs/ca-certificates.crt

# Add custom certificates to java keystore
RUN ${JAVA_HOME}/bin/keytool -import -trustcacerts -alias custom-root -keystore ${JAVA_HOME}/lib/security/cacerts -storepass changeit -noprompt -file /tmp/certs/root-CA.crt \
    && ${JAVA_HOME}/bin/keytool -import -trustcacerts -alias custom-sub02 -keystore ${JAVA_HOME}/lib/security/cacerts -storepass changeit -noprompt -file /tmp/certs/sub-02-CA.crt \
    && ${JAVA_HOME}/bin/keytool -import -trustcacerts -alias custom-powerscale -keystore ${JAVA_HOME}/lib/security/cacerts -storepass changeit -noprompt -file /tmp/certs/powerscale.crt

RUN awk -v cmd='openssl x509 -noout -subject' '/BEGIN/{close(cmd)};{print | cmd}' < /etc/ssl/certs/ca-certificates.crt > /tmp/ca.txt

RUN export CURL_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt


CMD [ "./run.sh" ]
