rebuild=false

working_dir=$(pwd)

# Parse options
while getopts ":r-rebuild" opt; do
  case ${opt} in
    r | rebuild ) 
      rebuild=true
      ;;
    \? ) 
      echo "Usage: $0 [-r | -rebuild]"
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


if [ "$rebuild" = true ]; then
    # Delete volumes if they exist
    if docker volume inspect postgres_db_data &>/dev/null; then
        echo "Removing postgres_db_data volume..."
        docker volume rm postgres_db_data
    fi
fi

# Start Postgres and pgAdmin
env PGADMIN_PATH="$working_dir/Microservices/.builds/postgres/pg_admin" PGADMIN_DEFAULT_EMAIL="pgadmin@pgadmin.com" \
    PGADMIN_DEFAULT_PASSWORD="pgadmin" DATABASE_NAME="TaskDB" DATABASE_USER="postgres" DATABASE_PASSWORD="postgres" docker stack deploy \
    --compose-file Microservices/.builds/postgres/postgres.stack.debug.yaml \
    postgres

# Run Schema Builders
if [ "$rebuild" = true ]; then
    cd Microservices/Authentication/src/Authentication.SchemaBuilder
    dotnet run
    cd ../../../../
fi
