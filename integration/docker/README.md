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

`Dockerfile-dev` extends the pinned multi-architecture alluxio-dev base image without reinstalling
or removing its packages. BuildKit compiles and embeds JNI FUSE independently for each requested
platform, replaces architecture-sensitive tini and async-profiler binaries, and runs the complete
native-image self-test before the image can be published.

Run the build from the repository root. No build arguments or separate verification command are required:

```console
$ docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -f integration/docker/Dockerfile-dev \
  -t registry.cn-hangzhou.aliyuncs.com/birdhk/alluxio-dev:2.9.0-fix.2 \
  --push .
```

For an optional post-publication audit of the manifest and both runnable images, use
`integration/docker/tests/verify-multiarch-dev-image.sh <image>`.

Loading a JNI library does not prove that it can exchange filesystem attributes with the host
kernel. Run the privileged StackFS check on a native host for each architecture before publishing:

```console
$ integration/docker/tests/verify-jni-fuse-mount.sh \
    <image> linux/amd64 x86_64 3
$ integration/docker/tests/verify-jni-fuse-mount.sh \
    <image> linux/arm64 aarch64 3
```

The multi-architecture workflow runs these checks on native `ubuntu-24.04` and
`ubuntu-24.04-arm` runners before the manifest build is allowed to publish.

The default base is pinned to the tested multi-architecture `2.9.0-fix.1` manifest. Override it
only when intentionally rebasing the compatibility image:

```console
$ docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -f integration/docker/Dockerfile-dev \
  --build-arg ALLUXIO_BASE_IMAGE=registry.example.com/alluxio/alluxio-dev:${old-version} \
  -t registry.example.com/alluxio/alluxio-dev:${new-version} \
  --push .
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
user. The compatibility `Dockerfile-dev` intentionally preserves the user from its base image.

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
