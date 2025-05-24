FROM debian:bookworm-slim

# Install dependencies and clean up in the same layer
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      unzip \
      wget && \
    rm -rf /var/lib/apt/lists/*

# Download and install protobuf-javascript  
RUN curl -OL https://github.com/protocolbuffers/protobuf-javascript/releases/download/v3.21.4/protobuf-javascript-3.21.4-linux-aarch_64.zip && \
    mkdir -p /usr/local/include && \
    unzip -o protobuf-javascript-3.21.4-linux-aarch_64.zip -d /usr/local bin/protoc-gen-js && \
    rm -rf protobuf-javascript-3.21.4-linux-aarch_64.zip

# Download and install protoc
RUN curl -OL https://github.com/protocolbuffers/protobuf/releases/download/v31.0/protoc-31.0-linux-aarch_64.zip && \
    unzip -o protoc-31.0-linux-aarch_64.zip -d /usr/local bin/protoc && \
    unzip -o protoc-31.0-linux-aarch_64.zip -d /usr/local include/* && \
    rm -rf protoc-31.0-linux-aarch_64.zip

# Download and install grpc-web plugin
RUN wget "https://github.com/grpc/grpc-web/releases/download/1.5.0/protoc-gen-grpc-web-1.5.0-linux-aarch64" --quiet && \
    mv protoc-gen-grpc-web-1.5.0-linux-aarch64 /usr/local/bin/protoc-gen-grpc-web && \
    chmod +x /usr/local/bin/protoc-gen-grpc-web

# Remove build dependencies
RUN apt-get purge -y \
        curl \
        unzip \
        wget && \
    apt-get autoremove -y && \
    rm -rf /var/lib/apt/lists/*

# Create non-root user
RUN useradd -m -d /home/protocuser protocuser
USER protocuser

WORKDIR /home/protocuser


ENTRYPOINT ["/usr/local/bin/protoc"]