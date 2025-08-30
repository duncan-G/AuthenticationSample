using System.Reflection;
using System.Text.Json;
using Amazon.Extensions.NETCore.Setup;
using Amazon.SecretsManager;
using Amazon.SecretsManager.Model;
using Amazon;
using Amazon.Runtime;
using FluentAssertions;
using Microsoft.Extensions.Configuration;
using Moq;
using Xunit;
using AuthSample.Api.Secrets;

namespace AuthSample.Api.Tests.Secrets;

public class SecretsManagerConfigurationProviderTests
{
    private static AWSOptions CreateAwsOptions()
    {
        return new AWSOptions
        {
            Region = RegionEndpoint.USEast1,
            Credentials = new AnonymousAWSCredentials()
        };
    }

    private static object CreateSource(AWSOptions awsOptions, AuthSample.Api.Secrets.SecretsManagerOptions options)
    {
        var sourceType = typeof(AuthSample.Api.Secrets.SecretsManagerOptions)
            .Assembly
            .GetType("AuthSample.Api.Secrets.SecretsManagerConfigurationSource", throwOnError: true)!;

        return Activator.CreateInstance(sourceType, awsOptions, options)!;
    }

    private static object BuildProvider(object source, IConfigurationBuilder builder)
    {
        var buildMethod = source.GetType().GetMethod("Build", BindingFlags.Instance | BindingFlags.Public)!;
        return buildMethod.Invoke(source, new object[] { builder })!;
    }

    private static void InjectClient(object provider, IAmazonSecretsManager client)
    {
        var field = provider.GetType().GetField("_client", BindingFlags.Instance | BindingFlags.NonPublic)!;
        var lazy = Activator.CreateInstance(typeof(Lazy<>).MakeGenericType(typeof(IAmazonSecretsManager)),
            new object[] { (Func<IAmazonSecretsManager>)(() => client) });
        field.SetValue(provider, lazy);
    }

    private static void Load(object provider)
    {
        ((IConfigurationProvider)provider).Load();
    }

    private static IReadOnlyDictionary<string, string?> ReadData(object provider)
    {
        var baseType = provider.GetType().BaseType!; // ConfigurationProvider
        var dataProp = baseType.GetProperty("Data", BindingFlags.Instance | BindingFlags.NonPublic)!;
        return (IReadOnlyDictionary<string, string?>)dataProp.GetValue(provider)!;
    }

    private static Mock<IAmazonSecretsManager> CreateSecretsClientMock(string secretId, params string[] secretJsons)
    {
        var mock = new Mock<IAmazonSecretsManager>(MockBehavior.Strict);
        var sequence = mock.SetupSequence(m => m.GetSecretValueAsync(
            It.Is<GetSecretValueRequest>(r => r.SecretId == secretId),
            It.IsAny<CancellationToken>()));

        foreach (var json in secretJsons)
        {
            sequence = sequence.ReturnsAsync(new GetSecretValueResponse { SecretString = json });
        }

        // Fallback if called more times than provided
        sequence.ReturnsAsync(new GetSecretValueResponse { SecretString = secretJsons.LastOrDefault() ?? "{}" });

        // Allow Dispose to be called by provider
        mock.Setup(m => m.Dispose());

        return mock;
    }

    [Fact]
    public void AddSecretsManager_should_throw_when_secretId_missing()
    {
        var builder = new ConfigurationBuilder();
        var aws = CreateAwsOptions();

        Action act = () => builder.AddSecretsManager(aws, _ => { });

        act.Should().Throw<InvalidOperationException>()
            .WithMessage("SecretId cannot be null or empty.");
    }

    [Fact]
    public void Should_load_shared_entries_with_key_replacement()
    {
        var secretId = "test/secret";
        var options = new AuthSample.Api.Secrets.SecretsManagerOptions
        {
            SecretId = secretId,
            UseDevOverrides = false,
            Prefix = null
        };

        var json = JsonSerializer.Serialize(new Dictionary<string, string?>
        {
            { "Shared_My__Section__Key", "value" },
            { "Shared_Empty", null }
        });

        var clientMock = CreateSecretsClientMock(secretId, json);
        var source = CreateSource(CreateAwsOptions(), options);
        var provider = BuildProvider(source, new ConfigurationBuilder());
        InjectClient(provider, clientMock.Object);

        Load(provider);

        var data = ReadData(provider);
        data.Should().ContainKey("My:Section:Key").WhoseValue.Should().Be("value");
        data.Should().NotContainKey("Empty");

        ((IDisposable)provider).Dispose();
    }

    [Fact]
    public void Should_apply_app_prefix_and_shared_entries()
    {
        var secretId = "test/secret";
        var options = new AuthSample.Api.Secrets.SecretsManagerOptions
        {
            SecretId = secretId,
            Prefix = "App_",
            UseDevOverrides = false
        };

        var json = JsonSerializer.Serialize(new Dictionary<string, string?>
        {
            { "App_Foo__Bar", "1" },
            { "Shared_Baz", "2" }
        });

        var clientMock = CreateSecretsClientMock(secretId, json);
        var source = CreateSource(CreateAwsOptions(), options);
        var provider = BuildProvider(source, new ConfigurationBuilder());
        InjectClient(provider, clientMock.Object);

        Load(provider);

        var data = ReadData(provider);
        data.Should().Contain(new KeyValuePair<string, string?>("Foo:Bar", "1"));
        data.Should().Contain(new KeyValuePair<string, string?>("Baz", "2"));

        ((IDisposable)provider).Dispose();
    }

    [Fact]
    public void Should_apply_dev_overrides_over_shared_and_app()
    {
        var secretId = "test/secret";
        var options = new AuthSample.Api.Secrets.SecretsManagerOptions
        {
            SecretId = secretId,
            Prefix = "App_",
            UseDevOverrides = true
        };

        var json = JsonSerializer.Serialize(new Dictionary<string, string?>
        {
            { "Shared_Foo", "baseA" },
            { "SharedOverride_Foo", "ovrA" },
            { "App_Bar", "baseB" },
            { "AppOverride_Bar", "ovrB" }
        });

        var clientMock = CreateSecretsClientMock(secretId, json);
        var source = CreateSource(CreateAwsOptions(), options);
        var provider = BuildProvider(source, new ConfigurationBuilder());
        InjectClient(provider, clientMock.Object);

        Load(provider);

        var data = ReadData(provider);
        data.Should().Contain(new KeyValuePair<string, string?>("Foo", "ovrA"));
        data.Should().Contain(new KeyValuePair<string, string?>("Bar", "ovrB"));

        ((IDisposable)provider).Dispose();
    }

    [Fact]
    public void Keys_should_be_case_insensitive()
    {
        var secretId = "test/secret";
        var options = new AuthSample.Api.Secrets.SecretsManagerOptions
        {
            SecretId = secretId,
            Prefix = null,
            UseDevOverrides = false
        };

        var json = JsonSerializer.Serialize(new Dictionary<string, string?>
        {
            { "Shared_Foo__Bar", "X" }
        });

        var clientMock = CreateSecretsClientMock(secretId, json);
        var source = CreateSource(CreateAwsOptions(), options);
        var provider = BuildProvider(source, new ConfigurationBuilder());
        InjectClient(provider, clientMock.Object);

        Load(provider);

        var data = ReadData(provider);
        data.Should().ContainKey("Foo:Bar");
        data.Should().ContainKey("foo:bar");
        data["foo:bar"].Should().Be("X");

        ((IDisposable)provider).Dispose();
    }

    [Fact]
    public async Task Should_reload_after_interval_and_update_values()
    {
        var secretId = "test/secret";
        var options = new AuthSample.Api.Secrets.SecretsManagerOptions
        {
            SecretId = secretId,
            ReloadAfter = TimeSpan.FromMilliseconds(100)
        };

        var first = JsonSerializer.Serialize(new Dictionary<string, string?>
        {
            { "Shared_Val", "1" }
        });
        var second = JsonSerializer.Serialize(new Dictionary<string, string?>
        {
            { "Shared_Val", "2" }
        });

        var clientMock = CreateSecretsClientMock(secretId, first, second, second);
        var source = CreateSource(CreateAwsOptions(), options);
        var provider = BuildProvider(source, new ConfigurationBuilder());
        InjectClient(provider, clientMock.Object);

        // Initial load
        Load(provider);
        ReadData(provider)["Val"].Should().Be("1");

        // Observe for next reload
        var changeNotified = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
        var tokenForNext = ((IConfigurationProvider)provider).GetReloadToken();
        tokenForNext.RegisterChangeCallback(_ => changeNotified.TrySetResult(true), state: null);

        await Task.WhenAny(changeNotified.Task, Task.Delay(3000));
        changeNotified.Task.IsCompleted.Should().BeTrue("a reload should have occurred");

        // After reload, value should be updated
        var data = ReadData(provider);
        data["Val"].Should().Be("2");

        ((IDisposable)provider).Dispose();
    }
}


