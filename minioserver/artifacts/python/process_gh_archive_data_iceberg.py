import argparse

import pyspark
from pyspark.sql import SparkSession
from pyspark import SparkContext
import pyspark.sql.functions as F
import pyspark.sql.types as T


JAR_PACKAGES = ("org.apache.iceberg:iceberg-spark-runtime-3.4_2.12:1.6.1",)

CREATE_TABLE_QUERY = """
CREATE TABLE IF NOT EXISTS iceberg_catalog.gh_archive (
    event_id STRING,
    event_type STRING,
    created_at TIMESTAMP,
    repository_id STRING,
    repository_name STRING,
    repository_url STRING,
    user_id STRING,
    user_name STRING,
    user_url STRING,
    user_avatar_url STRING,
    org_id STRING,
    org_name STRING,
    org_url STRING,
    org_avatar_url STRING,
    push_id STRING,
    number_of_commits LONG,
    language STRING,
    year INT,
    month INT,
    day INT,
    hour INT,
    minute INT,
    second INT
) USING iceberg
TBLPROPERTIES ('write.spark.accept-any-schema'='true')
PARTITIONED BY (year, month, day, hour);
"""

conf = (
    pyspark.SparkConf()
    .set("spark.jars.packages", ",".join(JAR_PACKAGES))
    .set(
        "spark.sql.extensions",
        "org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions",
    )
    .set("spark.sql.catalog.spark_catalog", "org.apache.iceberg.spark.SparkSessionCatalog")
    .set("spark.sql.catalog.spark_catalog.type", "hive")
    .set("spark.sql.catalog.iceberg_catalog", "org.apache.iceberg.spark.SparkCatalog")
    .set("spark.sql.catalog.iceberg_catalog.type", "hadoop")
    .set("spark.sql.catalog.iceberg_catalog.warehouse", "s3a://curated/iceberg/")
    .set("spark.sql.defaultCatalog", "iceberg_catalog")
)

## Start Spark Session
spark = SparkSession.builder.config(conf=conf).getOrCreate()
print("Spark Running")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--source_files_pattern",
        help="Source files pattern for the GH archive to process.",
        required=True,
    )

    args = parser.parse_args()

    read_filepath = args.source_files_pattern
    print(f"read_filepath: {read_filepath}")

    df = spark.read.json(read_filepath)

    allowed_events = [
        "PushEvent",
        "ForkEvent",
        "PublicEvent",
        "WatchEvent",
        "PullRequestEvent",
    ]

    main_df = df.select(
        F.col("id").alias("event_id"),
        F.col("type").alias("event_type"),
        F.to_timestamp(F.col("created_at"), "yyyy-MM-dd'T'HH:mm:ss'Z'").alias(
            "created_at"
        ),
        F.col("repo.id").astype(T.StringType()).alias("repository_id"),
        F.col("repo.name").alias("repository_name"),
        F.col("repo.url").alias("repository_url"),
        F.col("actor.id").astype(T.StringType()).alias("user_id"),
        F.col("actor.login").alias("user_name"),
        F.col("actor.url").alias("user_url"),
        F.col("actor.avatar_url").alias("user_avatar_url"),
        F.col("org.id").astype(T.StringType()).alias("org_id"),
        F.col("org.login").alias("org_name"),
        F.col("org.url").alias("org_url"),
        F.col("org.avatar_url").alias("org_avatar_url"),
        F.col("payload.push_id").astype(T.StringType()).alias("push_id"),
        F.col("payload.distinct_size").alias("number_of_commits"),
        F.col("payload.pull_request.base.repo.language").alias("language"),
    ).filter(F.col("type").isin(allowed_events))

    main_df = (
        main_df.withColumn("year", F.year("created_at"))
        .withColumn("month", F.month("created_at"))
        .withColumn("day", F.dayofmonth("created_at"))
        .withColumn("hour", F.hour("created_at"))
        .withColumn("minute", F.minute("created_at"))
        .withColumn("second", F.second("created_at"))
    )
    # add timestamp field
    main_df = main_df.withColumn(
        "ts",
        F.unix_timestamp("created_at", "yyyy-MM-dd'T'HH:mm:ss'Z'"),
    )

    spark.sql(CREATE_TABLE_QUERY).show()

    main_df.writeTo("iceberg_catalog.db.gh_archive").option("mergeSchema","true").overwritePartitions()
