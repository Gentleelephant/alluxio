## Prerequisite
To build your Alluxio Docker image, a Docker 19.03+ is required. 

## Building docker image for production
Run Docker builds from the repository root so the architecture-specific JNI FUSE sources are
available to the Docker build context. To build the Alluxio production image from the default
remote tarball, run
```console
$ docker build -t alluxio/alluxio -f integration/docker/Dockerfile --target final .
```

To build with a local Alluxio tarball, specify the `ALLUXIO_TARBALL` build argument

```console
$ docker build -t alluxio/alluxio -f integration/docker/Dockerfile --target final \
  --build-arg ALLUXIO_TARBALL=alluxio-${version}.tar.gz .
```

Starting from v2.6.0, alluxio-fuse image is deprecated. It is embedded in `alluxio/alluxio` image.

## Building docker image for development
Starting from now, Alluxio has a separate image for development usage. Unlike the default Alluxio 
Docker image that only installs packages needed for Alluxio service to run, this image installs 
more development tools, including gcc, make, async-profiler, etc., making it easier to deploy more 
services along with Alluxio.

The development image is a target of the same Dockerfile as the production image. This guarantees
that master, worker, CSI, and FUSE use the same architecture-correct runtime while retaining Java
8/11, GCC/G++, Make, CMake, Git, Vim, Arthas, and async-profiler. To build it, run
```console
$ docker build -t alluxio/alluxio-dev -f integration/docker/Dockerfile --target dev .
```

To build with a local Alluxio tarball, specify the `ALLUXIO_TARBALL` build argument

```console
$ docker build -t alluxio/alluxio-dev -f integration/docker/Dockerfile --target dev \
  --build-arg ALLUXIO_TARBALL=alluxio-${version}.tar.gz .
```

Development image also has Java11 installed. To run Alluxio with Java11, build development image 
with the `JAVA_VERSION` build argument specified.

```console
$ docker build -t alluxio/alluxio-dev -f integration/docker/Dockerfile --target dev \
  --build-arg ALLUXIO_TARBALL=alluxio-${version}.tar.gz \
  --build-arg JAVA_VERSION=11 .
```

To publish one tag for both supported CPU architectures, use Buildx. BuildKit executes the JNI
FUSE compilation independently in each target platform and publishes a manifest list containing
the two resulting images.

```console
$ docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -f integration/docker/Dockerfile \
  --target dev \
  -t registry.example.com/alluxio/alluxio-dev:${version} \
  --push .
```

After publishing, verify the manifest, development tools, native binaries, JAR fallback, and
external JNI loading on both platforms:

```console
$ integration/docker/tests/verify-multiarch-dev-image.sh \
  registry.example.com/alluxio/alluxio-dev:${version}
```

If an existing customized `alluxio-dev` image already contains required internal tools or
configuration, use `Dockerfile-dev` to preserve its packages, Java selection, Arthas, entrypoint,
user, and Alluxio files. This compatibility build replaces only the architecture-bound JNI FUSE
libraries, the copies embedded in the FUSE JAR, tini, and async-profiler. The base image must
already publish both platforms, and its CSI binary must already match each platform; the verifier
below rejects the result otherwise.

```console
$ docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -f integration/docker/Dockerfile-dev \
  --build-arg ALLUXIO_BASE_IMAGE=registry.example.com/alluxio/alluxio-dev:${old-version} \
  -t registry.example.com/alluxio/alluxio-dev:${new-version} \
  --push .
```

For the current customized image, run the build from the repository root:

```console
$ docker buildx create --name alluxio-multiarch --driver docker-container --use
$ docker buildx inspect --bootstrap
$ docker login registry.cn-hangzhou.aliyuncs.com
$ docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -f integration/docker/Dockerfile-dev \
  --build-arg ALLUXIO_BASE_IMAGE=registry.cn-hangzhou.aliyuncs.com/birdhk/alluxio-dev:2.9.0-fix.1 \
  -t registry.cn-hangzhou.aliyuncs.com/birdhk/alluxio-dev:2.9.0-fix.2 \
  --push .
$ integration/docker/tests/verify-multiarch-dev-image.sh \
  registry.cn-hangzhou.aliyuncs.com/birdhk/alluxio-dev:2.9.0-fix.2
```

The two download base URLs can be redirected to an internal mirror when the builder cannot access
GitHub. Preserve the upstream directory layout (`v0.18.0/...` and `v2.9/...`); SHA-256 and ELF
architecture checks still run during the build.

```console
$ docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -f integration/docker/Dockerfile-dev \
  --build-arg ALLUXIO_BASE_IMAGE=registry.example.com/alluxio/alluxio-dev:${old-version} \
  --build-arg TINI_DOWNLOAD_BASE=https://mirror.example.com/tini \
  --build-arg ASYNC_PROFILER_DOWNLOAD_BASE=https://mirror.example.com/async-profiler \
  -t registry.example.com/alluxio/alluxio-dev:${new-version} \
  --push .
```

To use a customized user/group to launch Alluxio inside containers, build the Dockerfile
with `--build-arg ALLUXIO_USERNAME=`, `--build-arg ALLUXIO_GROUP=`, etc. For example,
if you want to use user `alluxio2` with uid `1001` and group `alluxio2` with gid `1001`, run the following command:

```console
$ docker build -t alluxio/alluxio:customizedUser \
  -f integration/docker/Dockerfile --target final \
  --build-arg ALLUXIO_USERNAME=alluxio2 --build-arg ALLUXIO_UID=1001 \
  --build-arg ALLUXIO_GROUP=alluxio2 --build-arg ALLUXIO_GID=1001 .
```

Use the same arguments with the `dev` target to create a development image with a customized
user. The compatibility `Dockerfile-dev` requires `ALLUXIO_BASE_IMAGE` explicitly.

```console
$ docker build -t alluxio/alluxio-dev:customizedUser \
  -f integration/docker/Dockerfile --target dev \
  --build-arg ALLUXIO_USERNAME=alluxio2 --build-arg ALLUXIO_UID=1001 \
  --build-arg ALLUXIO_GROUP=alluxio2 --build-arg ALLUXIO_GID=1001 .
```

## Running docker image
The generated image expects to be run with single argument of "master", "worker", "proxy", or "fuse".
To set an Alluxio configuration property, convert it to an environment variable by uppercasing
and replacing periods with underscores. For example, `alluxio.master.hostname` converts to
`ALLUXIO_MASTER_HOSTNAME`. You can then set the environment variable on the image with
`-e PROPERTY=value`. Alluxio configuration values will be copied to `conf/alluxio-site.properties`
when the image starts.

```console
$ docker run -e ALLUXIO_MASTER_HOSTNAME=ec2-203-0-113-25.compute-1.amazonaws.com \
alluxio/alluxio-[
|dev] [master|worker|proxy|fuse]
```

Additional configuration files can be included when building the image by adding them to the
`integration/docker/conf/` directory. All contents of this directory will be
copied to `/opt/alluxio/conf`.

## Running docker image with FUSE support
There are a couple extra arguments required to run the docker image with FUSE support. For example,
to launch a standalone Fuse container:

```console
$ docker run -e ALLUXIO_MASTER_HOSTNAME=alluxio-master \
--cap-add SYS_ADMIN --device /dev/fuse alluxio/alluxio fuse --fuse-opts=allow_other
```

Note: running FUSE in docker requires adding
[SYS_ADMIN capability](http://man7.org/linux/man-pages/man7/capabilities.7.html) to the container.
This removes isolation of the container and should be used with caution.

## Extending docker image with applications
You can easily extend the docker image to include applications to run on top of Alluxio.
In order for the application to access data from Alluxio storage mounted with FUSE, it must run
in the same container as Alluxio FUSE. Simply edit `Dockerfile` to install the applications, and 
then build the image with the same command for building image with FUSE support and run it.

## More information
For more information on launching alluxio in docker containers, please refer to
https://docs.alluxio.io/os/user/stable/en/deploy/Running-Alluxio-On-Docker.html
