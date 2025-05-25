using AutoMapper;
using Google.Protobuf.Collections;

namespace AuthenticationSample.Api.Mapping;

/// <summary>
///     Mapping between IReadOnlyList and RepeatedField defined in Google.Protobuf.Collections
/// </summary>
public class ProtobufUser : Profile
{
    public ProtobufUser()
    {
        CreateMap(typeof(IReadOnlyList<>), typeof(RepeatedField<>))
            .ConvertUsing(typeof(ReadOnlyListToRepeatedFieldConverter<,>));
    }

    private class
        ReadOnlyListToRepeatedFieldConverter<TSource, TDest> : ITypeConverter<IReadOnlyList<TSource>,
        RepeatedField<TDest>>
    {
        public RepeatedField<TDest> Convert(IReadOnlyList<TSource> source, RepeatedField<TDest> destination,
            ResolutionContext context)
        {
            destination.AddRange(source.Select(item => context.Mapper.Map<TDest>(item)));
            return destination;
        }
    }
}