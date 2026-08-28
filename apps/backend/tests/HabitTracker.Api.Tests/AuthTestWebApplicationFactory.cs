using HabitTracker.Api.Data;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;

namespace HabitTracker.Api.Tests;

/// <summary>
/// A <see cref="WebApplicationFactory{TEntryPoint}"/> that swaps the Npgsql-backed
/// <see cref="HabitTrackerDbContext"/> registration for the EF Core in-memory provider, so the
/// HTTP-level auth tests need neither Docker nor a Postgres connection (a hard requirement from
/// apps/backend/CLAUDE.md). Each instance gets its own uniquely-named in-memory database, so two
/// tests each constructing their own factory never see one another's rows.
/// </summary>
internal sealed class AuthTestWebApplicationFactory : WebApplicationFactory<Program>
{
    private readonly string _databaseName = $"auth-endpoints-{Guid.NewGuid()}";

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.ConfigureServices(services =>
        {
            // EF Core's AddDbContext composes every registered configuration callback for a given
            // TContext rather than letting a later call override an earlier one (so that e.g.
            // AddDbContextPool + a test override can both contribute). Removing only
            // DbContextOptions<HabitTrackerDbContext> therefore isn't enough — Program.cs's
            // options.UseNpgsql(...) callback would still run alongside ours below, and EF Core
            // throws ("Only a single database provider can be registered") the moment both a
            // relational and the in-memory provider show up on the same context. Removing this
            // configuration-callback registration too is what actually drops the Npgsql callback.
            services.RemoveAll<DbContextOptions<HabitTrackerDbContext>>();
            services.RemoveAll<IDbContextOptionsConfiguration<HabitTrackerDbContext>>();
            services.AddDbContext<HabitTrackerDbContext>(options =>
                options.UseInMemoryDatabase(_databaseName)
            );
        });
    }
}
