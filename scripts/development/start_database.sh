clean_database=false

working_dir=$(pwd)

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

# Start Redis
env docker stack deploy --compose-file infrastructure/redis/redis.stack.debug.yaml redis

# Start DynamoDB Local
env docker stack deploy --compose-file infrastructure/dynamo-db/dynamo-db.stack.debug.yaml dynamo-db

# Run Schema Builders
if [ "$rebuild" = true ]; then
    cd microservices/Auth/src/Auth.SchemaBuilder
    dotnet run
    cd ../../../../
fi
