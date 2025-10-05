# Fabric Minecraft Server

This project is configured to run a Fabric Minecraft server either natively on Windows/Linux or within a Docker container.

## Initial Configuration

Before the first launch, you can pre-configure the server. All server data, including mods, configs, and worlds, will be stored in the `data` directory, which will be created on the first run if it doesn't exist.

- **Mods**: Place your mod `.jar` files in `data/mods/`.
- **Initial Properties**: To set server properties for the very first launch, create and edit `data/default-server.properties`. These values will be used to generate the primary `server.properties` file.
- **Ongoing Properties**: After the first launch, all server configuration should be done by editing `data/server.properties`.
- **World Data**: The Minecraft world folder will be located at `data/world/`.

## Running the Server

Choose one of the following methods to run the server.

### 1. Docker (Recommended)

This method isolates the server in a container for easy management. See the Docker section below for detailed commands.

```bash
# Start the server on the default port (25565)
docker-compose up -d
```

### 2. Linux (Native)

Execute the shell script. This requires Java to be installed on your system.

```bash
./start_linux.sh
```

### 3. Windows (Native)

Double-click or run `start_windows.bat`. This requires Java to be installed on your system.

```batch
.\start_windows.bat
```

## Docker Server Management

Use these commands from your project's root directory to manage the containerized server.

- **Start the Server**

  ```bash
  # Build and start a Docker container in the background.
  docker-compose up -d
  ```

- **Start on a Custom Port**

  ```bash
  # Run the server on host port 26656 (Windows CMD/PowerShell requires setting the variable first)
  MC_PORT=26656 docker-compose up -d
  ```

- **Stop the Server**

  ```bash
  # Stops the server gracefully and removes the container.
  docker-compose down
  ```

- **View Live Console**

  ```bash
  # Follow the real-time server logs. Press Ctrl+C to exit without stopping the server.
  docker-compose logs -f
  ```

- **Access Interactive Console**

  ```bash
  # Attach to the server to run commands (e.g., op, gamemode).
  docker-compose attach

  # To detach WITHOUT stopping the server, use the escape sequence: Ctrl+P, then Ctrl+Q
  ```

## Post-start admin commands

I use the following commands after creating a new server/world.

```
chunky start overworld circle 0 0 5000
chunky start the_nether circle 0 0 2000
chunky start the_end circle 0 0 2000
gamerule minecartMaxSpeed 50
gamerule spawnRadius 0
gamerule snowAccumulationHeight 7
function blazeandcave:config/intro_msg_off
function blazeandcave:config/item_rewards_off
function blazeandcave:config/exp_rewards_off
function blazeandcave:config/trophies_off
backup init
backup local
backup set shutdown-action local
backup set autoback-action local
backup set autoback-wait 30
backup set retention-policy gfs

# Restoring backups:
backup list
backup restore <name>
# Note: restore command will output the location of the restored backup, you have to manually delete the current world and copy the restored folder
```
