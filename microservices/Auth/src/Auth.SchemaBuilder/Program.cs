using Amazon.DynamoDBv2;
using Amazon.DynamoDBv2.Model;
using AuthSample.Auth.Infrastructure.DynamoDb;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;

const string tableName = "AuthSample_RefreshTokens";

using var host = Host.CreateDefaultBuilder(args)
    .ConfigureAppConfiguration((context, config) =>
    {
        config.AddJsonFile("appsettings.json", optional: true, reloadOnChange: false);
        config.AddJsonFile($"appsettings.{context.HostingEnvironment.EnvironmentName}.json", optional: true, reloadOnChange: false);
    })
    .ConfigureServices((context, services) =>
    {
        services.AddDynamoDb(context.HostingEnvironment, options => context.Configuration.Bind("DynamoDb", options));
    })
    .Build();

CancellationTokenSource cancellationTokenSource = new();

Console.CancelKeyPress += (_, e) =>
{
    Console.WriteLine("Cancellation requested. Running cleanup...");
    cancellationTokenSource.Cancel();
    e.Cancel = true;
};

try
{
    using var scope = host.Services.CreateScope();
    var dynamo = scope.ServiceProvider.GetRequiredService<IAmazonDynamoDB>();

    Console.WriteLine($"Ensuring DynamoDB table '{tableName}' exists...");

    var tables = await dynamo.ListTablesAsync(cancellationTokenSource.Token).ConfigureAwait(false);
    if (!tables.TableNames.Contains(tableName))
    {
        await dynamo.CreateTableAsync(new CreateTableRequest
        {
            TableName = tableName,
            AttributeDefinitions =
            [
                new AttributeDefinition("pk", ScalarAttributeType.S),
                new AttributeDefinition("sk", ScalarAttributeType.S)
            ],
            KeySchema =
            [
                new KeySchemaElement("pk", KeyType.HASH),
                new KeySchemaElement("sk", KeyType.RANGE)
            ],
            BillingMode = BillingMode.PAY_PER_REQUEST
        }, cancellationTokenSource.Token).ConfigureAwait(false);

        Console.WriteLine($"Created table '{tableName}'.");
    }
    else
    {
        Console.WriteLine($"Table '{tableName}' already exists.");
    }

    Console.WriteLine("DynamoDB initialization complete.");
}
catch (Exception ex)
{
    Console.WriteLine("DynamoDB initialization failed: " + ex.Message);
    return 1;
}

return 0;
