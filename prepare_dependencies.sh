#!/bin/bash
set -e

# Usage: ./prepare_dependencies.sh
# Downloads all external deps into ./dependencies/

# Create a directory for dependencies
DEPENDENCIES_DIR="./dependencies"
mkdir -p "$DEPENDENCIES_DIR"

# Download Python
PYTHON_URL="https://www.python.org/ftp/python/2.7.13/Python-2.7.13.tgz"
PYTHON_FILE="$DEPENDENCIES_DIR/Python-2.7.13.tgz"
if [ ! -f "$PYTHON_FILE" ]; then
  echo "Downloading Python..."
  wget --no-check-certificate "$PYTHON_URL" -O "$PYTHON_FILE"
fi

# Download JABAWS WAR file
WAR_URL="http://www.compbio.dundee.ac.uk/jabaws22/archive/jabaws.war"
WAR_FILE="$DEPENDENCIES_DIR/jabaws.war"
if [ ! -f "$WAR_FILE" ]; then
  echo "Downloading JABAWS WAR file..."
  wget "$WAR_URL" -O "$WAR_FILE"
fi

# Download config scripts
CONFIG_GUESS_URL="https://git.savannah.gnu.org/gitweb/?p=config.git;a=blob_plain;f=config.guess"
CONFIG_SUB_URL="https://git.savannah.gnu.org/gitweb/?p=config.git;a=blob_plain;f=config.sub"
if [ ! -f "$DEPENDENCIES_DIR/config.guess" ]; then
  echo "Downloading config.guess..."
  wget -qO "$DEPENDENCIES_DIR/config.guess" "$CONFIG_GUESS_URL"
fi
if [ ! -f "$DEPENDENCIES_DIR/config.sub" ]; then
  echo "Downloading config.sub..."
  wget -qO "$DEPENDENCIES_DIR/config.sub" "$CONFIG_SUB_URL"
fi

echo "All dependencies downloaded successfully."