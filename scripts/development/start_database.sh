clean_database=false

working_dir=$(pwd)

# Verify required environment variables
if [ -z "$DATABASE_NAME" ]; then
    echo "Error: DATABASE_NAME is not set in environment"
    exit 1
fi

if [ -z "$DATABASE_USER" ]; then
    echo "Error: DATABASE_USER is not set in environment"
    exit 1
fi

if [ -z "$DATABASE_PASSWORD" ]; then
    echo "Error: DATABASE_PASSWORD is not set in environment"
    exit 1
fi

# Parse options
while getopts ":c-clean" opt; do
  case ${opt} in
    c | clean ) 
      clean_database=true
      ;;
    \? ) 
      echo "Usage: $0 [-c | -clean]"
      exit 1
      ;;
  esac
done

# Shift parsed options so remaining arguments can be accessed
shift $((OPTIND -1))

# Check if postgres stack is running and remove it if it exists
if docker stack ps postgres &>/dev/null; then
    echo "Removing existing postgres stack..."
    docker stack rm postgres
fi

# Wait for postgres stack to be fully removed
while docker stack ps postgres &>/dev/null; do
    echo "Waiting for postgres stack to be removed..."
    sleep 2
done


if [ "$clean_database" = true ]; then
    # Delete volumes if they exist
    if docker volume inspect postgres_db_data &>/dev/null; then
        echo "Removing postgres_db_data volume..."
        docker volume rm postgres_db_data
    fi
fi

# Start Postgres and pgAdmin
env PGADMIN_PATH="$working_dir/microservices/.builds/postgres/pg_admin" \
    PGADMIN_DEFAULT_EMAIL=$PGADMIN_DEFAULT_EMAIL \
    PGADMIN_DEFAULT_PASSWORD=$PGADMIN_DEFAULT_PASSWORD \
    DATABASE_NAME=$DATABASE_NAME \
    DATABASE_USER=$DATABASE_USER \
    DATABASE_PASSWORD=$DATABASE_PASSWORD \
    docker stack deploy --compose-file infrastructure/postgres/postgres.stack.debug.yaml postgres

# Run Schema Builders
if [ "$rebuild" = true ]; then
    cd microservices/Auth/src/Auth.SchemaBuilder
    dotnet run
    cd ../../../../
fi
