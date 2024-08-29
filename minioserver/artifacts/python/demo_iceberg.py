import pyspark
from pyspark.sql import SparkSession


JAR_PACKAGES = ("iceberg-spark-runtime-3.5_2.12:1.6.0",)

CREATE_TABLE_QUERY = """
   CREATE TABLE IF NOT EXISTS iceberg_catalog.taxis (
         vendor_id long,
        trip_id long,
        trip_distance float,
        fare_amount double,
        store_and_fwd_flag string
   ) USING iceberg;
"""

conf = (
    pyspark.SparkConf()
    .set("spark.jars.packages", ",".join(JAR_PACKAGES))
    .set(
        "spark.sql.extensions",
        "org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions",
    )
    .set("spark.sql.catalog.iceberg_catalog", "org.apache.iceberg.spark.SparkCatalog")
    .set("spark.sql.catalog.iceberg_catalog.type", "hadoop")
    .set("spark.sql.catalog.iceberg_catalog.warehouse", "s3a://curated/iceberg/")
)

## Start Spark Session
spark = SparkSession.builder.config(conf=conf).getOrCreate()
print("Spark Running")

spark.sql(CREATE_TABLE_QUERY).show()

schema = spark.table("iceberg_catalog.taxis").schema
data = [
    (1, 1000371, 1.8, 15.32, "N"),
    (2, 1000372, 2.5, 22.15, "N"),
    (2, 1000373, 0.9, 9.01, "N"),
    (1, 1000374, 8.4, 42.13, "Y"),
]
df = spark.createDataFrame(data, schema)
df.writeTo("iceberg_catalog.taxis").partitionedBy("vendor_id").createOrReplace()