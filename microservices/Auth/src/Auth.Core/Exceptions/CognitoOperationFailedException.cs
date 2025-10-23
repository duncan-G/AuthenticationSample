using System.Net;

namespace AuthSample.Auth.Core.Exceptions;

public class CognitoOperationFailedException : Exception
{
    public CognitoOperationFailedException(
        string operationName,
        HttpStatusCode? statusCode = null,
        string? message = null,
        Exception? innerException = null) : base(message ?? $"Cognito operation '{operationName}' failed.",
        innerException)
    {
        OperationName = operationName;
        StatusCode = statusCode;
    }

    public string OperationName { get; }
    public HttpStatusCode? StatusCode { get; }
}
