using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Design;
using Microsoft.Extensions.Configuration;

namespace HabitTracker.Api.Data;

/// <summary>
/// Builds a <see cref="HabitTrackerDbContext"/> for EF Core design-time tools (<c>dotnet ef
/// migrations add</c>), independent of the app's DI container.
/// <para>
/// Design-time tooling normally resolves the context by building the whole host (<c>Program.cs</c>),
/// but that host wires up authentication, the rate limiter, and a <see cref="Services.CurrentUser"/>
/// built from an authenticated principal that doesn't exist at design time. None of that should be
/// a prerequisite for reading the EF model, so this factory sidesteps the host entirely, reading the
/// same connection string <c>Program.cs</c> uses straight from configuration.
/// </para>
/// </summary>
public class HabitTrackerDbContextFactory : IDesignTimeDbContextFactory<HabitTrackerDbContext>
{
    public HabitTrackerDbContext CreateDbContext(string[] args)
    {
        var configuration = new ConfigurationBuilder()
            .SetBasePath(AppContext.BaseDirectory)
            .AddJsonFile("appsettings.json", optional: true)
            .AddJsonFile("appsettings.Development.json", optional: true)
            .Build();

        var optionsBuilder = new DbContextOptionsBuilder<HabitTrackerDbContext>();
        optionsBuilder.UseNpgsql(configuration.GetConnectionString("HabitTracker"));

        return new HabitTrackerDbContext(optionsBuilder.Options);
    }
}
