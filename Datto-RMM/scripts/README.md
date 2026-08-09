This is just the PowerShell script for installing the Huntress Agent using AEM.

The component file includes the resource file which contains variables needed to run the script.

Please see the following document for usage details:
https://support.huntress.io/article/45-deploying-huntress-with-aem

This script will install the Huntress Agent on your computers. The variable HUNTRESS_ACCOUNT_KEY must be defined first. The DattoRMM site name will be used to associate the agent to an organization within the Huntress console. Any organizations that do not exist will be created automatically. See https://support.huntress.io/article/116-deploying-huntress-with-datto-rmm-comstore for complete details.

## Datto RMM components (`.cpt`)

### What a `.cpt` is

A `.cpt` is a plain zip archive packaged form of a Datto RMM (CentraStage) component.

| Entry | Purpose |
| --- | --- |
| `command.bat` | The script itself, stored verbatim. Despite the `.bat` extension it is **not** batch — for the Windows component it is the PowerShell script, and `<installType>powershell</installType>` in `resource.xml` is what tells Datto how to run it. Do not add batch (`.bat`) syntax. |
| `resource.xml` | Component metadata: display name, description, `uid`, version, timeout, the job variables shown in the Datto UI, and the postCondition. |
| `icon.png` | The component icon shown in the Datto UI. |

The components in this repo are:

- `Datto-RMM/Huntress Agent Deployment WIN.cpt` — script source of truth is
  `Datto-RMM/scripts/InstallHuntress.dattormm.comstore.ps1`
- `Datto-RMM/Mac/InstallHuntress-macOS-DattoRmm.cpt` — the unpacked files are also checked in
  alongside it in `Datto-RMM/Mac/`
