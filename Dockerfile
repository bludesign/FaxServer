FROM ubuntu:16.04

LABEL maintainer="bludesign"

# Set Default Timezone
RUN echo GMT > /etc/timezone

# Install CURL and tzdata
RUN apt-get update && \
    apt-get -y install curl libcurl4-openssl-dev tzdata && \
    rm -rf /var/lib/apt/lists/*;

# Configure tzdata
RUN dpkg-reconfigure -f noninteractive tzdata

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
