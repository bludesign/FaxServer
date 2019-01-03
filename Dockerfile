FROM ubuntu:16.04

LABEL maintainer="bludesign"

# Set Default Timezone
ENV TZ=GMT
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# Install CURL and tzdata
RUN apt-get update && \
    apt-get -y install wget curl openssl libssl-dev libcurl4-openssl-dev libavahi-compat-libdnssd-dev tzdata build-essential && \
    rm -rf /var/lib/apt/lists/*;

# Configure tzdata
RUN dpkg-reconfigure -f noninteractive tzdata

# Install libsodium
RUN wget https://download.libsodium.org/libsodium/releases/libsodium-1.0.16.tar.gz && \
    tar xzf libsodium-1.0.16.tar.gz && \
    cd libsodium-1.0.16 && \
    ./configure && \
    make && make check && \
    make install && \
    ldconfig

# Get Vapor repo including Swift
RUN curl -sL https://apt.vapor.sh | bash;

# Installing Swift & Vapor
RUN apt-get update && \
    apt-get -y install swift vapor && \
    rm -rf /var/lib/apt/lists/*;

# Clone and build Reaumur
RUN git clone https://github.com/bludesign/FaxServer.git
WORKDIR "/FaxServer"
RUN vapor build --release --verbose

# Serve
CMD bash -c ".build/release/App"
