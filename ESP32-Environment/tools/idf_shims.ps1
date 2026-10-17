# tools/idf_shims.ps1 - dot-sourced by run.ps1, run_wizard.ps1, menu.ps1 and
# every step run_gui.ps1 starts (oct. 17 2026).
#
# ESP-IDF's export.ps1 does not put idf.py / esptool.py on PATH as programs: it
# defines them as PowerShell FUNCTIONS in the ESP-IDF PowerShell window. A child
# PowerShell (the GUI runs every step in one) inherits the environment but not
# functions, and then:
#   - "idf.py" opens tools\idf.py through Windows' .py file association, which
#     re-splits the arguments - a build dir under "C:\Users\First Last\" arrived
#     as two arguments ("Error: No such option: -p", sniffer flash, oct. 17);
#   - "esptool.py" does not exist at all, so run.ps1's full chip erase silently
#     fell back to the serial DELETE_LOGS wipe.
# Same definitions as ESP-IDF's tools/export_utils/shell_types.py. Only defined
# when missing, so the real ESP-IDF window keeps its own.
if ($env:IDF_PATH) {
    if (-not (Get-Command idf.py -CommandType Function -ErrorAction SilentlyContinue)) {
        function global:idf.py { & python "$env:IDF_PATH\tools\idf.py" @args }
    }
    if (-not (Get-Command esptool.py -CommandType Function -ErrorAction SilentlyContinue)) {
        function global:esptool.py { & python -m esptool @args }
    }
}
