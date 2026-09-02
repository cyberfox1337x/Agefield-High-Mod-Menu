!macro cyberfox1337x_function MODULE_NAME
!macroend
!insertmacro cyberfox1337x_function "agefield_runtime_nsis"

!define AGEFIELD_RUNTIME_ROOT "$INSTDIR\resources\agefield-runtime"
!define AGEFIELD_RUNTIME_HELPER "${AGEFIELD_RUNTIME_ROOT}\AgefieldRuntimeInstaller.ps1"

!macro customInstall
  DetailPrint "Validating and installing the official Agefield High runtime..."
  nsExec::ExecToStack '"$SYSDIR\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "${AGEFIELD_RUNTIME_HELPER}" -Action Install -PayloadRoot "${AGEFIELD_RUNTIME_ROOT}" -ApplicationVersion "${VERSION}"'
  Pop $0
  Pop $1
  ${If} $0 != 0
    MessageBox MB_ICONSTOP|MB_OK "The Agefield runtime was not installed.$\r$\n$\r$\n$1"
    Abort
  ${EndIf}
!macroend

!macro customUnInstall
  DetailPrint "Restoring the pre-install Agefield High runtime state..."
  nsExec::ExecToStack '"$SYSDIR\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "${AGEFIELD_RUNTIME_HELPER}" -Action Uninstall'
  Pop $0
  Pop $1
  ${If} $0 != 0
    MessageBox MB_ICONSTOP|MB_OK "The Agefield runtime could not be restored, so the menu was not uninstalled.$\r$\n$\r$\n$1"
    Abort
  ${EndIf}
!macroend
