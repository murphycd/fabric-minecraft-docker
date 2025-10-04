# Use an official Java 21 runtime as a parent image
FROM eclipse-temurin:21-jre-jammy

# Define an argument for the port with a default value
ARG MC_PORT=25565
# Set it as an environment variable for the image
ENV MC_PORT=${MC_PORT}

# Install dependencies: curl for downloading, and git + git-lfs for mods/backups.
RUN apt-get update && apt-get install -y curl git git-lfs && \
    # Initialize git-lfs for all users in the image
    git lfs install && \
    # Clean up apt cache to keep the image size down
    rm -rf /var/lib/apt/lists/*

# Set the working directory for the application runner
WORKDIR /server

# Copy the launch script into the image's application directory.
COPY start_linux.sh ./

# Make the launch script executable.
RUN chmod +x start_linux.sh

# The script will create and manage a 'data' subdirectory.
# We create a mount point for the volume here.
RUN mkdir -p /server/data
VOLUME /server/data

# Expose the internal ports the server will run on.
EXPOSE ${MC_PORT}

# Set the entrypoint to our launch script.
# The script will then change directory into the 'data' volume to run the server.
ENTRYPOINT ["/server/start_linux.sh"]
