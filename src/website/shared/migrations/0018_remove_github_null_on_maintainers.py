# Generated by Django 4.2.7 on 2023-12-10 13:08

from django.db import migrations, models


def drop_improper_maintainers(apps, schema_editor):
    Maintainer = apps.get_model("shared", "NixMaintainer")
    db_alias = schema_editor.connection.alias
    Maintainer.objects.using(db_alias).filter(github=None).delete()
    Maintainer.objects.using(db_alias).filter(github_id=None).delete()


class Migration(migrations.Migration):
    dependencies = [
        ("shared", "0016_cveingestion_cverecord_triaged"),
    ]

    operations = [
        migrations.SeparateDatabaseAndState(
            state_operations=[
                migrations.RunPython(drop_improper_maintainers),
            ],
            database_operations=[
                migrations.AlterField(
                    model_name="nixmaintainer",
                    name="github",
                    field=models.CharField(max_length=200, unique=True),
                ),
                migrations.AlterField(
                    model_name="nixmaintainer",
                    name="github_id",
                    field=models.IntegerField(unique=True),
                ),
            ],
        ),
    ]
