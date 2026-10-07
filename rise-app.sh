#!/bin/bash
#
# rise-app.sh -- build the Rise app image, or deploy it to the appserver
#
# Usage: bash rise-app.sh build    build the image (this also runs the tests)
#        bash rise-app.sh deploy   copy the image to the appserver and start it
#
# The deploy step logs in on the appserver over SSH. In Jenkins, the key comes
# from the credential `appserver-deploy` (see the Jenkinsfile).

set -euo pipefail

readonly image=riseapp
readonly container=riserunning
# Docker volume on the appserver that holds the SQLite database, so the data
# survives a new deployment
readonly volume=rise_data
readonly port=5001
readonly appserver_ip="${APPSERVER_IP:-172.16.0.20}"
readonly appserver="deploy@${appserver_ip}"

# Run a command on the appserver. BatchMode: fail instead of asking for a
# password or to confirm the host key, Jenkins can't answer.
on_appserver() {
  ssh -o BatchMode=yes "${appserver}" "$@"
}

build() {
  # Start from a clean tempdir, so the script can be run more than once
  rm -rf tempdir
  mkdir tempdir

  # Copy everything that is needed to build into the tempdir folder
  cp Rise.sln tempdir/.
  cp -r src tempdir/.
  cp -r tests tempdir/.

  # Generate the Dockerfile
  cat > tempdir/Dockerfile << _EOF_
# ---------- Stage 1: build ----------
# Pulls the image with the full .NET 10 SDK (compiler, dotnet CLI, NuGet)
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build

# Sets the working directory
WORKDIR /src

# Copy the build context (tempdir) into /src.
COPY . .

# Download all NuGet packages
RUN dotnet restore Rise.sln

# Compile and run all unit tests
RUN dotnet test Rise.sln --no-restore

# Compile Rise.Server in Release mode and put the result in /app/publish.
RUN dotnet publish src/Rise.Server/Rise.Server.csproj -c Release -o /app/publish --no-restore

# ---------- Stage 2: runtime ----------
# Much smaller image: only the ASP.NET runtime, no SDK or source code.
FROM mcr.microsoft.com/dotnet/aspnet:10.0

#Creates and navigates to the container's execution directory
WORKDIR /app

# Take only the compiled output from the build stage.
COPY --from=build /app/publish .

# Keep the SQLite database in /app/data instead of next to the app, so a
# volume can be mounted there and the data survives a new container.
RUN mkdir -p /app/data
ENV ConnectionStrings__DatabaseConnection="DataSource=/app/data/Rise.db;Cache=Shared"

# Let the server listen on port 5001 on all network interfaces (+), plain HTTP.
ENV ASPNETCORE_URLS=http://+:${port}

# Run in the Development environment (migrations and seeding only run there).
ENV ASPNETCORE_ENVIRONMENT=Development

# Documents that the container uses port 5001.
EXPOSE ${port}

# Command that starts when the container starts: run the compiled server.
CMD ["dotnet", "Rise.Server.dll"]
_EOF_

  docker build -t "${image}" tempdir
}

deploy() {
  # Stream the image to the appserver; `docker load` accepts gzip directly.
  echo "Copying image ${image} to ${appserver_ip}"
  docker save "${image}" | gzip | on_appserver docker load

  # Replace the running container. `docker rm` fails if there is none yet.
  echo "Starting container ${container} on ${appserver_ip}"
  on_appserver docker rm --force "${container}" || true
  on_appserver docker run --detach \
    --name "${container}" \
    --restart unless-stopped \
    --publish "${port}:${port}" \
    --volume "${volume}:/app/data" \
    "${image}"

  # The previous image is now untagged, clean it up
  on_appserver docker image prune --force

  # Check that the app answers (it needs a few seconds to start)
  echo "Waiting for http://${appserver_ip}:${port}/"
  for _ in $(seq 1 30); do
    if curl --fail --silent --output /dev/null "http://${appserver_ip}:${port}/"; then
      echo "The app is up at http://${appserver_ip}:${port}/"
      return 0
    fi
    sleep 2
  done
  echo "The app did not answer within 60 seconds" >&2
  on_appserver docker logs --tail 50 "${container}" >&2
  return 1
}

case "${1:-}" in
  build) build ;;
  deploy) deploy ;;
  *)
    echo "Usage: $0 build|deploy" >&2
    exit 1
    ;;
esac
