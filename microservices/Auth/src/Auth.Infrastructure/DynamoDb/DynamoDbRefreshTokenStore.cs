using Amazon.DynamoDBv2;
using Amazon.DynamoDBv2.Model;
using AuthSample.Auth.Core.Identity;
using Microsoft.Extensions.Logging;

namespace AuthSample.Auth.Infrastructure.DynamoDB;

public sealed class DynamoDbRefreshTokenStore(
    IAmazonDynamoDB dynamoDb,
    ILogger<DynamoDbRefreshTokenStore> logger) : IRefreshTokenStore
{
    private const string TableName = "AuthSample_RefreshTokens";

    public async Task SaveAsync(RefreshTokenRecord record, CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(record.RtId) ||
            string.IsNullOrWhiteSpace(record.UserSub) ||
            string.IsNullOrWhiteSpace(record.RefreshToken))
        {
            throw new ArgumentException("RefreshTokenRecord contains empty required fields (RtId, UserSub, RefreshToken)");
        }

        var item = new Dictionary<string, AttributeValue>
        {
            ["pk"] = new() { S = $"RTID#{record.RtId}" },
            ["sk"] = new() { S = $"v1" },
            ["userSub"] = new() { S = record.UserSub },
            ["refreshToken"] = new() { S = record.RefreshToken },
            ["issuedAtUtc"] = new() { S = record.IssuedAtUtc.ToString("O") },
        };

        try
        {
            await dynamoDb.PutItemAsync(new PutItemRequest
            {
                TableName = TableName,
                Item = item,
                ConditionExpression = "attribute_not_exists(pk) AND attribute_not_exists(sk)"
            }, cancellationToken).ConfigureAwait(false);
        }
        catch (ConditionalCheckFailedException)
        {
            logger.LogWarning("Refresh token already exists for rtId {RtId}", record.RtId);
        }
    }

    public async Task<RefreshTokenRecord?> GetAsync(string rtId, CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(rtId))
        {
            throw new ArgumentException("rtId must be provided", nameof(rtId));
        }

        var request = new GetItemRequest
        {
            TableName = TableName,
            Key = new Dictionary<string, AttributeValue>
            {
                ["pk"] = new() { S = $"RTID#{rtId}" },
                ["sk"] = new() { S = "v1" }
            },
            ConsistentRead = true
        };

        var response = await dynamoDb.GetItemAsync(request, cancellationToken).ConfigureAwait(false);
        if (response.Item == null || response.Item.Count == 0)
        {
            return null;
        }

        var item = response.Item;
        var userSub = item.TryGetValue("userSub", out var userSubAttr) ? userSubAttr.S : null;
        var refreshToken = item.TryGetValue("refreshToken", out var rtAttr) ? rtAttr.S : null;
        var issuedAtStr = item.TryGetValue("issuedAtUtc", out var issuedAttr) ? issuedAttr.S : null;
        var expiresAtStr = item.TryGetValue("expiresAtUtc", out var expiresAttr) ? expiresAttr.S : null;

        if (string.IsNullOrWhiteSpace(userSub) || string.IsNullOrWhiteSpace(refreshToken))
        {
            logger.LogWarning("Refresh token record for rtId {RtId} missing required attributes", rtId);
            return null;
        }

        DateTime issuedAtUtc = DateTime.MinValue;
        DateTime expiresAtUtc = DateTime.MinValue;
        if (!string.IsNullOrWhiteSpace(issuedAtStr))
        {
            DateTime.TryParse(issuedAtStr, out issuedAtUtc);
        }
        if (!string.IsNullOrWhiteSpace(expiresAtStr))
        {
            DateTime.TryParse(expiresAtStr, out expiresAtUtc);
        }

        return new RefreshTokenRecord(rtId, userSub!, refreshToken!, issuedAtUtc, expiresAtUtc);
    }
}
