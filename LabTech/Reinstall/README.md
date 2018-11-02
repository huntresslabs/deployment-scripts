# Automate (LabTech) Script for Re-Installing the Huntress Agent

**NOTE:** In most cases, you do not need to use this script. This script is meant to re-install the Huntress Agent. It does not check if the Huntress Agent is already installed. If run repeatedly (e.g. on a schedule), it will keep re-installing the agent.

For normal deployments please use:
https://github.com/huntresslabs/deployment-scripts/tree/master/LabTech

## Overview

This script will download the most recent Huntress Agent installer from the Huntress servers and run the installer. The installer will overwrite any previously installed version of the Huntress Agent. It will not change any existing agent's configuration.

- [Update Huntress Agent - Download.xml](https://raw.githubusercontent.com/huntresslabs/deployment-scripts/master/LabTech/Reinstall/Update%20Huntress%20Agent%20-%20Download.xml)

The setup is the same as the normal deployment script. You will need to update the script with your Huntress account key. When scheduled, it should only be run once.

Please see the following document for usage details:
https://support.huntress.io/article/41-deploying-huntress-via-labtech-automate
