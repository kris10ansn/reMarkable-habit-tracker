using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.OpenApi;
using Microsoft.OpenApi;

namespace HabitTracker.Api.Authentication;

/// <summary>
/// Describes the bearer scheme in the committed <c>openapi.json</c>, so a generated client (mobile's
/// kubb layer) knows to send <c>Authorization: Bearer &lt;token&gt;</c>. Registered in
/// <c>Program.cs</c> as both a document transformer (adds the scheme once) and an operation
/// transformer (attaches it to every operation except those marked <c>[AllowAnonymous]</c>), since
/// the fallback authorization policy makes every endpoint protected by default.
/// </summary>
public sealed class BearerSecuritySchemeTransformer : IOpenApiDocumentTransformer, IOpenApiOperationTransformer
{
    public Task TransformAsync(
        OpenApiDocument document,
        OpenApiDocumentTransformerContext context,
        CancellationToken cancellationToken
    )
    {
        document.Components ??= new OpenApiComponents();
        document.Components.SecuritySchemes ??= new Dictionary<string, IOpenApiSecurityScheme>();
        document.Components.SecuritySchemes[BearerTokenDefaults.AuthenticationScheme] = new OpenApiSecurityScheme
        {
            Type = SecuritySchemeType.Http,
            Scheme = "bearer",
            Description =
                "Opaque session token from /api/auth/signup, /api/auth/login, or an approved "
                + "pairing poll. Send as `Authorization: Bearer <token>`.",
        };

        return Task.CompletedTask;
    }

    public Task TransformAsync(
        OpenApiOperation operation,
        OpenApiOperationTransformerContext context,
        CancellationToken cancellationToken
    )
    {
        var isAnonymous = context
            .Description.ActionDescriptor.EndpointMetadata.OfType<IAllowAnonymous>()
            .Any();
        if (isAnonymous)
        {
            return Task.CompletedTask;
        }

        operation.Security ??= [];
        operation.Security.Add(
            new OpenApiSecurityRequirement
            {
                [
                    new OpenApiSecuritySchemeReference(
                        BearerTokenDefaults.AuthenticationScheme,
                        context.Document,
                        null
                    )
                ] = [],
            }
        );

        return Task.CompletedTask;
    }
}
