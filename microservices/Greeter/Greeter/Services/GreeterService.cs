using AuthSample.Greeter.Protos;
using Grpc.Core;

namespace AuthSample.Greeter.Services;

public class GreeterService(ILogger<GreeterService> logger) : Protos.Greeter.GreeterBase
{
    private static readonly string[] Greetings =
    [
        "Hello, {0}! Welcome to our service.",
        "Hi there, {0}! Great to see you.",
        "Greetings, {0}! How are you today?",
        "Hey {0}! Thanks for using our app.",
        "Good day, {0}! Hope you're doing well.",
        "Hello {0}! Nice to meet you.",
        "Hi {0}! What brings you here today?",
        "Welcome, {0}! Enjoy your stay.",
        "Hey there, {0}! We're glad you're here.",
        "Hello {0}! Ready to get started?",
        "Hi {0}! Thanks for choosing us.",
        "Welcome back, {0}! How can we help?",
        "Greetings {0}! We're excited to serve you.",
        "Hello {0}! Let's make something great.",
        "Hi there, {0}! Your journey begins here.",
        "Welcome {0}! We've been expecting you.",
        "Hey {0}! Ready for an amazing experience?",
        "Hello {0}! Let's create something special.",
        "Hi {0}! Your success is our priority.",
        "Welcome aboard, {0}! Let's begin."
    ];

    private static readonly Random Random = new();

    public override Task<HelloReply> SayHello(HelloRequest request, ServerCallContext context)
    {
        logger.LogInformation("SayHello called with name: {Name}", request.Name);

        string message;
        if (Random.NextDouble() < 0.8)
        {
            // Use regular greeting 80% of the time
            var greeting = Greetings[Random.Next(Greetings.Length)];
            message = string.Format(greeting, request.Name);
        }
        else
        {
            // Special responses 20% of the time
            var name = request.Name.ToLower();
            if (name.Contains("world"))
            {
                message = $"Hello, {request.Name}! You've got the whole world in your name! 🌍";
            }
            else if (name.Contains("test"))
            {
                message = $"Testing, testing... Hello {request.Name}! 🧪";
            }
            else if (request.Name.Length > 15)
            {
                message = $"Wow, {request.Name}, that's quite a long name! Hello there! 📏";
            }
            else if (string.IsNullOrWhiteSpace(request.Name))
            {
                message = "Hello, mysterious stranger! What should I call you?";
            }
            else
            {
                message = $"{request.Name}? That's a wonderful name! Hello! ✨";
            }
        }

        return Task.FromResult(new HelloReply { Message = message });
    }
}
