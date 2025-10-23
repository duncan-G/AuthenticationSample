using Amazon.DynamoDBv2;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;

namespace AuthSample.Auth.Infrastructure.DynamoDb;

public static class DynamoDbServiceCollectionExtensions
{
    public static IServiceCollection AddDynamoDb(
        this IServiceCollection services,
        IHostEnvironment environment,
        Action<DynamoDbOptions> configureOptions)
    {
        var options = new DynamoDbOptions { ServiceUrl = string.Empty };
        configureOptions(options);

        if (environment.IsDevelopment())
        {
            services.AddSingleton<IAmazonDynamoDB>(_ => new AmazonDynamoDBClient(new AmazonDynamoDBConfig
            {
                ServiceURL = options.ServiceUrl,
                Timeout = TimeSpan.FromSeconds(options.TimeoutSeconds),
                MaxErrorRetry = options.MaxErrorRetry
            }));
        }
        else
        {
            services.AddAWSService<IAmazonDynamoDB>();
        }

        return services;
    }
}
