Set WshShell = WScript.CreateObject("WScript.Shell")
Return = WshShell.Run("perlshare.bat", 0, True)
set WshShell = Nothing
