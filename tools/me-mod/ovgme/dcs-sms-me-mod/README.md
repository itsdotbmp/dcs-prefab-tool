# dcs-sms-me-mod (OvGME package skeleton)

This folder is the skeleton for an OvGME-installable copy of the dcs-sms
Mission Editor mod.

**v1 ships the folder structure only.** The CLI (`dcs-sms install-me-mod`)
is the supported install path because it patches your CURRENT
`MissionEditor.lua` rather than shipping a frozen copy that goes stale on
every DCS patch.

To assemble an OvGME bundle by hand, see the "OvGME (DIY for v1)" section
in `tools/me-mod/README.md`.
