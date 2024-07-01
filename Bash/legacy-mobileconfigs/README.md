# Legacy Mobileconfigs

These are kept around for legacy usage in the `legacy-mobileconfigs` folder.

## Do not use these these files unless you are specifically directed to by Huntress Support

- `Huntress PPPC.mobileconfig`: This payload will grant the Huntress agent FDA (full disk access). **This file does not configure the System Extension** and should be used for deployments that only use the Huntress Agent. Use `HuntressSystemExtension.mobileconfig` instead if you want the full capabilities of Huntress.

- `HuntressLegacyAgentProfile.mobileconfig`: A legacy profile used for versions of the Huntress macOS Agent before version `0.13.72`. Kept around for historical reasons, no customers should use this unless expressly directed to by Huntress Support.
