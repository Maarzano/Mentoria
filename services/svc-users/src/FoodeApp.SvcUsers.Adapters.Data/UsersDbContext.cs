using FoodeApp.Svcusers.Domain.Entities;
using FoodeApp.Svcusers.Domain.ValueObjects;
using Microsoft.EntityFrameworkCore;

namespace FoodeApp.Svcusers.Adapters.Data;

/// <summary>
/// DbContext do write side — usado exclusivamente pelos Command handlers.
/// Mapeamento explícito de colunas: sem convenções implícitas para manter
/// controle total sobre o schema (ADR-003).
/// </summary>
internal sealed class usersDbContext(DbContextOptions<usersDbContext> options) : DbContext(options)
{
    public DbSet<User> Users => Set<User>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<User>(entity =>
        {
            entity.ToTable("users", "users");

            entity.HasKey(u => u.Id);

            entity.Property(u => u.Id)
                  .HasColumnName("id");

            entity.Property(u => u.ZitadelUserId)
                  .HasColumnName("zitadel_user_id")
                  .IsRequired();

            entity.HasIndex(u => u.ZitadelUserId)
                  .IsUnique();

            entity.Property(u => u.DisplayName)
                  .HasColumnName("display_name")
                  .IsRequired();

            entity.Property(u => u.AvatarUrl)
                  .HasColumnName("avatar_url");

            entity.Property(u => u.Phone)
                  .HasColumnName("phone")
                  .HasConversion(
                      p => p != null ? p.Value : null,
                      s => s != null ? PhoneNumber.Create(s).Value : null);

            entity.Property(u => u.Role)
                  .HasColumnName("role")
                  .HasColumnType("text")
                  .HasConversion(
                      r => r.ToDbValue(),
                      s => UserRoleExtensions.Parse(s))
                  .IsRequired();

            entity.Property(u => u.CreatedAt)
                  .HasColumnName("created_at");

            entity.Property(u => u.UpdatedAt)
                  .HasColumnName("updated_at");

            entity.Ignore(u => u.DomainEvents);
        });
    }
}
