![Workshop Image](static/image.png)

<div align="center">

# Workshop Ubucon Latinoamérica 2024

</div>

Este es el repositorio para el taller de Ubucon Latinoamérica 2024 titulado:

📊 Crea tu propio laboratorio de Big Data con MicroK8s y Spark

El enlace al video de la charla se encuentra [aqui](https://www.youtube.com/watch?v=kSlLjAXISA8). Recomendamos ver el video de la presentación antes de iniciar el taller.

## Requisitos

> **Disclaimer**: Este proyecto no ejecuta en Windows.

**Hardware:**

Se recomienda que se ejecute en una máquina externa que mínimo tenga:

- +8 GB RAM.
- +2 CPU.
- +20GB almacenamiento.

**Software:**

Se recomienda correr el taller en una máquina con Ubuntu 22.04 o superior. Adicionalmente instalar el paquete de Snap. Para instalar Snap en tu máquina puedes seguir este enlace: [Instalar Snap](https://snapcraft.io/docs/installing-snapd).

Para verificar que tienes instalado Snap en tu máquina puedes ejecutar el siguiente comando:

```bash
snap --version
```

## Inicializar el proyecto

1. Ejecute el archivo `setup.sh` para desplegar los componentes de Kmicrok8s, asi como el cliente de spark.

    ```bash
    bash setup.sh
    ```

2. Ejecute el archivo `init_project.sh` para poder configurar los buckets de S3 en MinIO y configurar spark.

    ```bash
    bash init_project.sh
    ```

3. Cargar códigos de prueba, con el script `upload_artifacts.sh`

    ```bash
    bash upload_artifacts.sh
    ```

4. Cargar los datos de prueba, con el script `upload_data.sh`

    ```bash
    bash upload_data.sh
    ```

## Prueba

Para iniciar la terminal de pyspark ejecute en siguiente comando en otra terminal

    ```bash
    spark-client.pyspark --username spark --namespace spark
    ```

Deberías tener una salida como esta:

```
Welcome to
      ____              __
     / __/__  ___ _____/ /__
    _\ \/ _ \/ _ `/ __/  '_/
   /__ / .__/\_,_/_/ /_/\_\   version 3.4.2
      /_/

Using Python version 3.10.12 (main, Jul 29 2024 16:56:48)
Spark context Web UI available at http://192.168.0.13:4040
Spark context available as 'sc' (master = k8s://https://192.168.0.13:16443, app id = spark-6af6f8c7a9104948a91c73443c85333d).
SparkSession available as 'spark'.
>>>
```

### Ejecute los archivos de Demo

ejecute el archivo `count_vowels.py`

```bash
spark-client.spark-submit \
--username spark --namespace spark \
--deploy-mode cluster \
s3a://artifacts/python/count_vowels.py
```

Para poder ver el resultado ejecuta:

```bash
pod_name=$(kubectl get pods -n spark | grep 'count-vowels-.*-driver' | tail -n 1 | cut -d' ' -f1)

# View only the line containing the output
kubectl logs $pod_name -n spark | grep "The number of vowels in the string is"
```

### Ejecutar archivo de procesamiento

Ahora bien, vamos a ejecutar un archivo para procesar datos

```bash
spark-client.spark-submit \
    --username spark --namespace spark \
    --deploy-mode cluster \
    s3a://artifacts/python/process_gh_archive_data.py \
    --source_files_pattern=s3a://raw/gh_archive/year=2024/month=01/day=01/hour=0 \
    --destination_files_pattern=s3a://curated/parquet/gh_archive
```

Esta ejecución crea uno o varios archivos en formato Parquet  en la ruta S3 `s3a://curated/parquet/gh_archive`

Ejecutemos ahora otra hora:

```bash
!spark-client.spark-submit \
    --username spark --namespace spark \
    --deploy-mode cluster \
    s3a://artifacts/python/process_gh_archive_data.py \
    --source_files_pattern=s3a://raw/gh_archive/year=2024/month=01/day=01/hour=1 \
    --destination_files_pattern=s3a://curated/parquet/gh_archive
```

### Demo Iceberg

Podemos ejecutar un archivo que no guarde en un formato como Parquet, sino en otros sistemas de archivos preparados para Big Data, como Apache Iceberg:

Ejecute el siguiente comando

```bash
spark-client.spark-submit \
    --username spark --namespace spark \
    --deploy-mode cluster \
    --packages org.apache.iceberg:iceberg-spark-runtime-3.4_2.12:1.6.1 \
    s3a://artifacts/python/demo_iceberg.py
```

Ahora procesa los datos de GH archive, pero en Iceberg:

```bash
spark-client.spark-submit \
    --username spark --namespace spark \
    --deploy-mode cluster \
    s3a://artifacts/python/process_gh_archive_data_iceberg.py \
    --source_files_pattern=s3a://raw/gh_archive/year=2024/month=01/day=02
```

# Referencias:

https://canonical.com/data/docs/spark/k8s/t-overview
