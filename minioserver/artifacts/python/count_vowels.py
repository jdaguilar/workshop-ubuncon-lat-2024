from operator import add
from pyspark.sql import SparkSession


def count_vowels(text: str) -> int:
    count = 0
    for char in text:
        if char.lower() in "aeiou":
            count += 1
    return count


# Create a Spark session
spark = SparkSession.builder.appName("CountVowels").getOrCreate()

lines = """Canonical's Charmed Data Platform solution for Apache Spark runs Spark jobs on your Kubernetes cluster.
You can get started right away with MicroK8s - the mightiest tiny Kubernetes distro around!
The spark-client snap simplifies the setup process to run Spark jobs against your Kubernetes cluster.
Spark on Kubernetes is a complex environment with many moving parts.
Sometimes, small mistakes can take a lot of time to debug and figure out.
"""

n = spark.sparkContext.parallelize(lines.splitlines(), 2).map(count_vowels).reduce(add)
print(f"The number of vowels in the string is {n}")

spark.stop()
