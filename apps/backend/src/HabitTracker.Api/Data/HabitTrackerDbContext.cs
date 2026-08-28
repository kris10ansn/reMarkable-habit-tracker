using HabitTracker.Api.Entities;
using Microsoft.EntityFrameworkCore;

namespace HabitTracker.Api.Data;

// No habits are seeded — a new user starts empty, and a first Sync from a client populates the
// canonical store.
public class HabitTrackerDbContext : DbContext
{
    public HabitTrackerDbContext(DbContextOptions<HabitTrackerDbContext> options)
        : base(options) { }

    public DbSet<User> Users => Set<User>();
    public DbSet<Habit> Habits => Set<Habit>();
    public DbSet<Entry> Entries => Set<Entry>();
    public DbSet<Session> Sessions => Set<Session>();
    public DbSet<Invite> Invites => Set<Invite>();
    public DbSet<PairingCode> PairingCodes => Set<PairingCode>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<User>(user =>
        {
            user.HasKey(u => u.Id);
            user.Property(u => u.Name).HasMaxLength(120);
            user.Property(u => u.Email).HasMaxLength(256).IsRequired();
            user.HasIndex(u => u.Email).IsUnique();
            user.Property(u => u.PasswordHash).IsRequired();
            user.Property(u => u.IsAdmin).HasDefaultValue(false);
        });

        modelBuilder.Entity<Habit>(habit =>
        {
            habit.HasKey(h => h.Id);
            habit.Property(h => h.Name).HasMaxLength(200).IsRequired();
            habit.Property(h => h.Polarity).HasConversion<string>().HasMaxLength(16);
            habit
                .HasOne(h => h.User)
                .WithMany(u => u.Habits)
                .HasForeignKey(h => h.UserId)
                .OnDelete(DeleteBehavior.Cascade);
            habit.HasIndex(h => new { h.UserId, h.Position });
        });

        modelBuilder.Entity<Entry>(entry =>
        {
            entry.HasKey(e => new { e.HabitId, e.Date });
            entry.Property(e => e.Outcome).HasConversion<string>().HasMaxLength(16);
            entry
                .HasOne(e => e.Habit)
                .WithMany(h => h.Entries)
                .HasForeignKey(e => e.HabitId)
                .OnDelete(DeleteBehavior.Cascade);
        });

        // Server-clock rows (Session, Invite, PairingCode) are configured below. None of them
        // implement ITimestamped — their CreatedAt/ExpiresAt/etc. are stamped explicitly by the
        // services that create them, not by StampTimestamps.

        modelBuilder.Entity<Session>(session =>
        {
            session.HasKey(s => s.Id);
            session.Property(s => s.TokenHash).HasMaxLength(64).IsRequired();
            session.HasIndex(s => s.TokenHash).IsUnique();
            session.Property(s => s.DeviceName).HasMaxLength(120).IsRequired();
            session
                .HasOne(s => s.User)
                .WithMany(u => u.Sessions)
                .HasForeignKey(s => s.UserId)
                .OnDelete(DeleteBehavior.Cascade);
        });

        modelBuilder.Entity<Invite>(invite =>
        {
            invite.HasKey(i => i.Id);
            invite.Property(i => i.Code).HasMaxLength(32).IsRequired();
            invite.HasIndex(i => i.Code).IsUnique();
            // No inverse collections on User for either FK below — keep User uncluttered, per
            // apps/backend/CLAUDE.md. Both FKs point at User, so each is configured explicitly.
            invite
                .HasOne(i => i.CreatedByUser)
                .WithMany()
                .HasForeignKey(i => i.CreatedByUserId)
                .OnDelete(DeleteBehavior.Cascade);
            invite
                .HasOne(i => i.UsedByUser)
                .WithMany()
                .HasForeignKey(i => i.UsedByUserId)
                .OnDelete(DeleteBehavior.SetNull);
            // Concurrency token: redemption reads "UsedByUserId == null" and then writes it, and
            // without this, EF's UPDATE would only ever key on Id, so a second signup racing the
            // same code re-evaluates a WHERE clause that never mentions UsedByUserId and silently
            // overwrites the first redeemer. With this annotation EF adds
            // "AND UsedByUserId IS NULL" to the UPDATE's WHERE clause, so the loser affects 0 rows
            // and gets DbUpdateConcurrencyException instead of quietly winning (see
            // AuthService.SignupAsync). Do not remove this as a "redundant" column check.
            invite.Property(i => i.UsedByUserId).IsConcurrencyToken();
        });

        modelBuilder.Entity<PairingCode>(pairingCode =>
        {
            pairingCode.HasKey(p => p.Id);
            pairingCode.Property(p => p.Code).HasMaxLength(16).IsRequired();
            pairingCode.HasIndex(p => p.Code).IsUnique();
            pairingCode.Property(p => p.DeviceName).HasMaxLength(120).IsRequired();
            // No inverse collection on User — keep User uncluttered, per apps/backend/CLAUDE.md.
            pairingCode
                .HasOne(p => p.ApprovedByUser)
                .WithMany()
                .HasForeignKey(p => p.ApprovedByUserId)
                .OnDelete(DeleteBehavior.Cascade);
        });
    }

    public override Task<int> SaveChangesAsync(CancellationToken cancellationToken = default)
    {
        StampTimestamps();
        return base.SaveChangesAsync(cancellationToken);
    }

    public override int SaveChanges()
    {
        StampTimestamps();
        return base.SaveChanges();
    }

    private void StampTimestamps()
    {
        var now = DateTimeOffset.UtcNow;

        foreach (var entry in ChangeTracker.Entries<ITimestamped>())
        {
            // Only stamp a create-time nobody supplied. A row arriving over Sync carries the
            // creating client's own CreatedAt, which must survive verbatim — mobile anchors a
            // negative habit's streak on it, so re-stamping it here would move the anchor to
            // whenever the device happened to sync.
            if (entry.State == EntityState.Added && entry.Entity.CreatedAt == default)
            {
                entry.Entity.CreatedAt = now;
            }

            if (entry.State is EntityState.Added or EntityState.Modified)
            {
                entry.Entity.UpdatedAt = now;
            }
        }
    }
}
