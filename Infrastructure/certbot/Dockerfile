FROM certbot/dns-route53:latest

# Add dependencies
RUN apk update && \
    apk add --no-cache bash && \
    apk add --no-cache curl && \
    apk add --no-cache jq && \
    apk add --no-cache py3-pip

# Install AWS CLI
RUN pip3 install --no-cache-dir awscli

WORKDIR /app

# Copy scripts
ADD renew-certificate.sh renew-certificate.sh

RUN chmod +x renew-certificate.sh && \
    mkdir /app/certs && \
    chmod +x /app/certs && \
    mkdir -p /var/log && \
    chmod 755 /var/log

ENTRYPOINT ["/app/renew-certificate.sh"]
