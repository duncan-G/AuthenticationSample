using System.Threading;
using System.Threading.Tasks;

namespace AuthSample.Auth.Core.Identity;

public interface IRefreshTokenStore
{
    Task SaveAsync(RefreshTokenRecord record, CancellationToken cancellationToken = default);
    Task<RefreshTokenRecord?> GetAsync(string rtId, CancellationToken cancellationToken = default);
}


