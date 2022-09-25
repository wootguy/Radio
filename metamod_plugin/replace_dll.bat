cd "C:\Games\Steam\steamapps\common\Sven Co-op\svencoop\addons\metamod\dlls"

if exist Radio_old.dll (
    del Radio_old.dll
)
if exist Radio.dll (
    rename Radio.dll Radio_old.dll 
)
