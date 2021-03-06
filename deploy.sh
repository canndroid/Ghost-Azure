#!/bin/bash

# ----------------------
# KUDU Deployment Script
# Version: 0.2.2
# ----------------------

# Helpers
# -------

exitWithMessageOnError () {
  if [ ! $? -eq 0 ]; then
    echo "ERROR: exit 1: An error has occurred during web site deployment."
    echo $1
    exit 1
  fi
}

# Prerequisites
# -------------

# Verify node.js installed
hash node 2>/dev/null
exitWithMessageOnError "Missing node.js executable, please install node.js, if already installed make sure it can be reached from current environment."

# Setup
# -----

SCRIPT_DIR="${BASH_SOURCE[0]%\\*}"
SCRIPT_DIR="${SCRIPT_DIR%/*}"
ARTIFACTS=$SCRIPT_DIR/../artifacts
KUDU_SYNC_CMD=${KUDU_SYNC_CMD//\"}

if [[ ! -n "$DEPLOYMENT_SOURCE" ]]; then
  DEPLOYMENT_SOURCE=$SCRIPT_DIR
fi

if [[ ! -n "$DEPLOYMENT_TARGET" ]]; then
  DEPLOYMENT_TARGET=$ARTIFACTS/wwwroot
else
### not sure about this variable whether required?
  KUDU_SERVICE=true
fi

if [[ ! -n "$NEXT_MANIFEST_PATH" ]]; then
  NEXT_MANIFEST_PATH=$ARTIFACTS/manifest

  if [[ ! -n "$PREVIOUS_MANIFEST_PATH" ]]; then
    PREVIOUS_MANIFEST_PATH=$NEXT_MANIFEST_PATH
  fi
fi

if [[ ! -n "$KUDU_SYNC_CMD" ]]; then
  # Install kudu sync
  echo Installing Kudu Sync
  npm install kudusync -g --silent
  exitWithMessageOnError "npm failed"

  if [[ ! -n "$KUDU_SERVICE" ]]; then
    # In case we are running on kudu service this is the correct location of kuduSync
    KUDU_SYNC_CMD=/usr/local/lib/node_modules/kudusync/bin/kudusync
  fi
fi

# Node Helpers
# ------------

selectNodeVersion () {
  if [[ -n "$KUDU_SELECT_NODE_VERSION_CMD" ]]; then
    echo "a here"
    echo "KUDU_SELECT_NODE_VERSION_CMD $KUDU_SELECT_NODE_VERSION_CMD"
    echo "DEPLOYMENT_SOURCE $DEPLOYMENT_SOURCE"
    echo "DEPLOYMENT_TARGET $DEPLOYMENT_TARGET"
    echo "DEPLOYMENT_TEMP $DEPLOYMENT_TEMP"
    
    # export WEBSITE_NODE_DEFAULT_VERSION=12
    # export WEBSITE_NPM_DEFAULT_VERSION=6
    echo "WEBSITE_NODE_DEFAULT_VERSION $WEBSITE_NODE_DEFAULT_VERSION"
    echo "WEBSITE_NPM_DEFAULT_VERSION $WEBSITE_NPM_DEFAULT_VERSION"
    
    SELECT_NODE_VERSION="$KUDU_SELECT_NODE_VERSION_CMD \"$DEPLOYMENT_SOURCE\" \"$DEPLOYMENT_TARGET\" \"$DEPLOYMENT_TEMP\""
    eval $SELECT_NODE_VERSION
    exitWithMessageOnError "select node version failed"

    if [[ -e "$DEPLOYMENT_TEMP/__nodeVersion.tmp" ]]; then
      NODE_EXE=`cat "$DEPLOYMENT_TEMP/__nodeVersion.tmp"`
      exitWithMessageOnError "getting node version failed"
    fi

    if [[ -e "$DEPLOYMENT_TEMP/__npmVersion.tmp" ]]; then
      NPM_JS_PATH=`cat "$DEPLOYMENT_TEMP/__npmVersion.tmp"`
      exitWithMessageOnError "getting npm version failed"
    fi

    if [[ ! -n "$NODE_EXE" ]]; then
      NODE_EXE=node
    fi

    NPM_CMD="\"$NODE_EXE\" \"$NPM_JS_PATH\""
  else
    echo "b here"
    NPM_CMD=npm
    NODE_EXE=node
  fi
}

##################################################################################################################################
# Deployment
# ----------

echo Handling node.js deployment.

# 1. KuduSync
if [[ "$IN_PLACE_DEPLOYMENT" -ne "1" ]]; then
  "$KUDU_SYNC_CMD" -v 50 -f "$DEPLOYMENT_SOURCE" -t "$DEPLOYMENT_TARGET" -n "$NEXT_MANIFEST_PATH" -p "$PREVIOUS_MANIFEST_PATH" -i ".git;.hg;.deployment;deploy.sh"
  exitWithMessageOnError "Kudu Sync failed"
fi

# 2. Select node version
# selectNodeVersion
    NPM_CMD=npm
    NODE_EXE=node

# 3. Install NPM packages
if [ -e "$DEPLOYMENT_TARGET/package.json" ]; then
  cd "$DEPLOYMENT_TARGET"
  eval $NPM_CMD config set openssl-root "$DEPLOYMENT_TARGET/openssl" -g
  eval $NPM_CMD config set scripts-prepend-node-path true
  eval $NPM_CMD config set audit false
  eval $NPM_CMD config set loglevel silent
  eval $NPM_CMD install --production --no-package-lock
  eval $NPM_CMD prune
  exitWithMessageOnError "npm failed"
  cd - > /dev/null
fi

# 4. Handle database creation and migrations.
if [ -e "$DEPLOYMENT_TARGET/db.js" ]; then
  cd "$DEPLOYMENT_TARGET"
  eval $NODE_EXE db.js
  exitWithMessageOnError "db creation failed"
  cd - > /dev/null
fi

##################################################################################################################################

# Post deployment stub
if [[ -n "$POST_DEPLOYMENT_ACTION" ]]; then
  POST_DEPLOYMENT_ACTION=${POST_DEPLOYMENT_ACTION//\"}
  cd "${POST_DEPLOYMENT_ACTION_DIR%\\*}"
  "$POST_DEPLOYMENT_ACTION"
  exitWithMessageOnError "post deployment action failed"
fi

echo "Finished successfully."
