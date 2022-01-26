FROM ubuntu:20.04 as build

ARG DEBIAN_FRONTEND=noninteractive
# Install various dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
        openjdk-11-jdk-headless \
		maven \
		wget \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# Resolve dependencies
COPY ./pom.xml pom.xml
RUN mvn --quiet dependency:resolve

# Copy the code
COPY ./src src
COPY ./assembly.xml assembly.xml
COPY ./cantaloupe.properties.sample cantaloupe.properties.sample
COPY ./delegates.rb.sample delegates.rb.sample
COPY ./CHANGES.md CHANGES.md
COPY ./LICENSE.txt LICENSE.txt
COPY ./LICENSE-3RD-PARTY.txt LICENSE-3RD-PARTY.txt
COPY ./README.md README.md
COPY ./UPGRADING.md UPGRADING.md

RUN mvn clean package -DskipTests
COPY target/cantaloupe-*.jar cantaloupe.jar

WORKDIR /dpkg
# Get GrokProcessor dependencies
RUN wget -q https://github.com/GrokImageCompression/grok/releases/download/v7.6.5/libgrokj2k1_7.6.5-1_amd64.deb \
    && wget -q https://github.com/GrokImageCompression/grok/releases/download/v7.6.5/grokj2k-tools_7.6.5-1_amd64.deb

FROM ubuntu:20.04 as runtime

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    openjdk-11-jre \
    ffmpeg \
    libopenjp2-tools \
    liblcms2-dev \
    libpng-dev \
    libzstd-dev \
    libtiff-dev \
    libjpeg-dev \
    zlib1g-dev \
    libwebp-dev \
    libimage-exiftool-perl \
    && rm -rf /var/lib/apt/lists/*

# Install TurboJpegProcessor dependencies
RUN mkdir -p /opt/libjpeg-turbo/lib
COPY docker/Linux-JDK11/image_files/libjpeg-turbo/lib64 /opt/libjpeg-turbo/lib
# Install KakaduNativeProcessor dependencies
COPY dist/deps/Linux-x86-64/lib/* /usr/lib/

# Install GrokProcessor dependencies
WORKDIR /dpkg
COPY --from=build /dpkg/* /dpkg/
RUN dpkg -i ./libgrokj2k1_7.6.5-1_amd64.deb \
    && dpkg -i --ignore-depends=libjpeg62-turbo ./grokj2k-tools_7.6.5-1_amd64.deb

# Configure persistence directorys, logging and deployment location
ARG user=cantaloupe
ARG deploymentPath=/home/$user
ARG logPath=/var/log/cantaloupe
ARG cachePath=/var/cache/cantaloupe
ARG configPath=/etc/cantaloupe

RUN mkdir -p $deploymentPath $logPath $cachePath $configPath

RUN adduser $user
RUN chown -R $user $deploymentPath $logPath $cachePath $configPath

ENV LOG_APPLICATION_LEVEL=info
ENV LOG_APPLICATION_ROLLINGFILEAPPENDER_ENABLED=true
ENV LOG_APPLICATION_ROLLINGFILEAPPENDER_PATHNAME=$logPath/application.log
ENV LOG_APPLICATION_ROLLINGFILEAPPENDER_TIMEBASEDROLLINGPOLICY_FILENAME_PATTERN=$logPath/application-%d{yyyy-MM-dd}.log

ENV LOG_ERROR_ROLLINGFILEAPPENDER_ENABLED=true
ENV LOG_ERROR_ROLLINGFILEAPPENDER_PATHNAME=$logPath/error.log
ENV LOG_ERROR_ROLLINGFILEAPPENDER_TIMEBASEDROLLINGPOLICY_FILENAME_PATTERN=$logPath/error-%d{yyyy-MM-dd}.log

ENV LOG_ACCESS_ROLLINGFILEAPPENDER_ENABLED=true
ENV LOG_ACCESS_ROLLINGFILEAPPENDER_PATHNAME=$logPath/access.log
ENV LOG_ACCESS_ROLLINGFILEAPPENDER_TIMEBASEDROLLINGPOLICY_FILENAME_PATTERN=$logPath/access-%d{yyyy-MM-dd}.log

# Can be overridden by mounting a custom config to $configPath/cantaloupe.properties
COPY ./cantaloupe.properties.sample $configPath/cantaloupe.properties

# Copy the application from the build stage
USER $user
WORKDIR $deploymentPath
COPY --from=build /build/cantaloupe.jar cantaloupe.jar

ENTRYPOINT [ "java", "-cp", "cantaloupe.jar", "-Dcantaloupe.config=/etc/cantaloupe/cantaloupe.properties", "edu.illinois.library.cantaloupe.StandaloneEntry" ]


