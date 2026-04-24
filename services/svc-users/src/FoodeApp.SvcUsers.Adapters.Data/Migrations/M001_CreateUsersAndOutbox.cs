using FluentMigrator;

namespace FoodeApp.Svcusers.Adapters.Data.Migrations;

[Migration(1, "Create users schema, users table and outbox_messages table")]
public sealed class M001_CreateUsersAndOutbox : Migration
{
    public override void Up()
    {
        Execute.Sql("CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\";");
        Execute.Sql("CREATE SCHEMA IF NOT EXISTS users;");

        Create.Table("users").InSchema("users")
            .WithColumn("id").AsGuid().PrimaryKey()
            .WithColumn("zitadel_user_id").AsString().NotNullable().Unique()
            .WithColumn("display_name").AsString().NotNullable()
            .WithColumn("avatar_url").AsString().Nullable()
            .WithColumn("phone").AsString().Nullable()
            .WithColumn("role").AsString().NotNullable()
            .WithColumn("created_at").AsDateTimeOffset().NotNullable().WithDefault(SystemMethods.CurrentUTCDateTime)
            .WithColumn("updated_at").AsDateTimeOffset().NotNullable().WithDefault(SystemMethods.CurrentUTCDateTime);

        Execute.Sql("ALTER TABLE users.users ADD CONSTRAINT chk_role CHECK (role IN ('comprador', 'lojista'));");

        Create.Table("outbox_messages").InSchema("users")
            .WithColumn("id").AsGuid().PrimaryKey().WithDefaultValue(SystemMethods.NewGuid)
            .WithColumn("type").AsString().NotNullable()
            .WithColumn("payload").AsCustom("JSONB").NotNullable()
            .WithColumn("created_at").AsDateTimeOffset().NotNullable().WithDefault(SystemMethods.CurrentUTCDateTime)
            .WithColumn("published_at").AsDateTimeOffset().Nullable()
            .WithColumn("retry_count").AsInt32().NotNullable().WithDefaultValue(0);
    }

    public override void Down()
    {
        Delete.Table("outbox_messages").InSchema("users");
        Delete.Table("users").InSchema("users");
        Execute.Sql("DROP SCHEMA IF EXISTS users;");
    }
}
