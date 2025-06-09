FROM postgres:17

# Update package list and install pg_cron and pgvector
RUN apt-get update && \
    apt-get install -y postgresql-17-cron postgresql-17-pgvector && \
    rm -rf /var/lib/apt/lists/*