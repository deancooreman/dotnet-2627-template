#!/bin/bash

set -euo pipefail

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

# Let the server listen on port 5001 on all network interfaces (+), plain HTTP.
ENV ASPNETCORE_URLS=http://+:5001

# Run in the Development environment (migrations and seeding only run there).
ENV ASPNETCORE_ENVIRONMENT=Development

# Documents that the container uses port 5001.
EXPOSE 5001

# Command that starts when the container starts: run the compiled server.
CMD ["dotnet", "Rise.Server.dll"]
_EOF_

cd tempdir || exit
docker build -t riseapp .
docker run -t -d -p 5001:5001 --name riserunning riseapp
docker ps -a
